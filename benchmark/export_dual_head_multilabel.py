"""Export ONNX du modele tajwid MULTI-LABEL (2026-07-24) -- remplace le CTC+
softmax (export_dual_head_checkpoint.py) par des sigmoides INDEPENDANTES par
classe, cf. finetune_dual_head.py::_tajwid_loss pour le POURQUOI complet.

Modele source : models/fastconformer-dual-head-v1/stagea-multilabel-v1/
    stagea-final.nemo        -> encodeur + tete 1 (INCHANGEE, gelee pendant
                                 l'entrainement -- identique a mixed-e14)
    stagea-tajwid-head.pt    -> tete 2 (19 classes, 17 regles + waqf_lazim +
                                 waqf_awla, SANS blank -- sigmoide, pas CTC)

⚠️ MEME PIEGE QUE TOUJOURS (2026-07-13, 2026-07-19) : entree `audio_signal`
(mel deja calcule), jamais `raw_audio`.

── DEUX SORTIES ──
    "logprobs"        (B, T, 1024+1) -- lettres+harakat, INCHANGE
    "tajwid_logprobs" (B, T,   19)   -- log_sigmoid PAR CLASSE, INDEPENDANT
                                        (0 = classe confidemment presente,
                                        tres negatif = absente ; PAS de
                                        normalisation entre classes -- deux
                                        classes peuvent valoir 0 sur la MEME
                                        frame, contrairement a l'ancien
                                        softmax qui les forcait a se
                                        partager une masse de probabilite).
Cote app (Kotlin) : le decodage doit donc appliquer un SEUIL PAR CLASSE
independant (ex. logsigmoid > log(0.5) = 0), plus un argmax global -- cf.
ForcedAligner.kt (a adapter separement).

Sorties ecrites :
    model.onnx   (les deux tetes, encodeur partage -- un seul passage)
    vocab.json   (1024 tokens de la tete 1, comme avant)
    rules.json   (les 19 noms de classes, dans l'ordre des ids de la tete 2)

Verification obligatoire avant deploiement (doit afficher audio_signal) :
  python3 -c "import onnxruntime as ort; \
    print([i.name for i in ort.InferenceSession('<model.onnx>').get_inputs()])"
"""
import os, json, random
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import torch
import torch.nn as nn
import numpy as np
import nemo.collections.asr as nemo_asr
from pathlib import Path
from finetune_dual_head import ConvTajwidHead

BASE_DIR = Path(__file__).parent
SRC_DIR = BASE_DIR / "models" / "fastconformer-dual-head-v1" / "stagea-multilabel-v3-cleanbase"
NEMO_PATH = SRC_DIR / "stagea-final.nemo"
HEAD_PATH = SRC_DIR / "stagea-tajwid-head.pt"
TAJWID_HEAD_HIDDEN = 256  # doit correspondre a --head_hidden du training
DEPLOY_DIR = (BASE_DIR / "models" / "fastconformer-dual-head-v1" / "deploy"
              / "fastconformer-ctc-dual-head-multilabel-v3")
OUT_ONNX = DEPLOY_DIR / "model.onnx"
OUT_VOCAB = DEPLOY_DIR / "vocab.json"
OUT_RULES = DEPLOY_DIR / "rules.json"

# Surcharge par CLI (2026-07-26) : le meme wrapper sert desormais au modele
# CAUSAL de stage B, dont l'encodeur porte deja sa config causale dans le
# .nemo. Les defauts ci-dessus sont inchanges -> un appel sans argument
# reproduit exactement l'export stage A d'origine.
#
# --causal_context : sur un encodeur causal, `att_context_size` doit etre fixe
# AVANT la trace ONNX, sinon la valeur embarquee est celle du dernier tirage
# multi-lookahead du training (le graphe exporte serait muet sur ce point et on
# ne s'en apercevrait qu'au comportement). Export SANS etat (segment complet) :
# c'est ce que la chaine Kotlin actuelle sait consommer, cf. la note
# `_kModelSubdir` dans app/lib/services/fastconformer_verifier.dart.

RULE_CLASSES = [
    "madda_necessary", "madda_obligatory", "madda_permissible", "madda_normal",
    "ghunnah", "ikhafa", "ikhafa_shafawi", "idgham_ghunnah", "idgham_shafawi",
    "iqlab", "idgham_wo_ghunnah", "idgham_mutajanisayn", "idgham_mutaqaribayn",
    "laam_shamsiyah", "ham_wasl", "slnt", "qalaqah",
    "waqf_lazim", "waqf_awla",
]
N_RULES = len(RULE_CLASSES)


class DualHeadWrapper(nn.Module):
    """encoder(audio_signal=mel, length) -> DEUX decodeurs sur le MEME
    encodage. Pas de preprocessor : le mel arrive deja calcule de l'app."""

    def __init__(self, model, tajwid_head):
        super().__init__()
        self.encoder = model.encoder
        self.ctc_decoder = model.ctc_decoder
        self.tajwid_head = tajwid_head

    def forward(self, audio_signal: torch.Tensor, length: torch.Tensor):
        encoded, encoded_len = self.encoder(audio_signal=audio_signal,
                                            length=length)
        logits = self.ctc_decoder(encoder_output=encoded)
        letters = torch.nn.functional.log_softmax(logits, dim=-1)
        tajwid_logits = self.tajwid_head(encoded.transpose(1, 2))
        # log_sigmoid, PAS log_softmax : chaque classe est INDEPENDANTE des
        # autres (cf. docstring) -- 0 = confidemment presente, tres negatif
        # = absente, sans normalisation croisee entre classes.
        tajwid = torch.nn.functional.logsigmoid(tajwid_logits)
        return letters, tajwid


def greedy_letters(logprobs, blank_id):
    ids = logprobs[0].argmax(axis=-1)
    out, prev = [], None
    for i in ids:
        if i != prev and i != blank_id:
            out.append(int(i))
        prev = i
    return out


def multilabel_rules(tajwid_logp, threshold=0.5):
    """Pour verification seulement : quelles classes depassent [threshold]
    de probabilite (logsigmoid > log(threshold)) sur AU MOINS une frame --
    contrairement a l'ancien greedy(), plusieurs classes peuvent ressortir
    sur la MEME frame (c'est le but)."""
    thr = float(np.log(threshold))
    active = (tajwid_logp[0] > thr).any(axis=0)
    return [RULE_CLASSES[i] for i in range(N_RULES) if active[i]]


def main():
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument("--nemo", default=str(NEMO_PATH))
    ap.add_argument("--head", default=str(HEAD_PATH))
    ap.add_argument("--out_dir", default=str(DEPLOY_DIR))
    ap.add_argument("--head_hidden", type=int, default=TAJWID_HEAD_HIDDEN)
    ap.add_argument("--causal_context", default=None,
                    help="ex. '70,13' -- fixe att_context_size avant la trace "
                         "(modele causal uniquement, cf. en-tete)")
    a = ap.parse_args()

    deploy_dir = Path(a.out_dir)
    out_onnx = deploy_dir / "model.onnx"
    out_vocab = deploy_dir / "vocab.json"
    out_rules = deploy_dir / "rules.json"
    deploy_dir.mkdir(parents=True, exist_ok=True)

    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        str(a.nemo), map_location="cpu")
    model.eval()
    model.preprocessor.featurizer.dither = 0.0
    if a.causal_context:
        ctx = [int(x) for x in a.causal_context.split(",")]
        model.encoder.set_default_att_context_size(ctx)
        print(f"contexte d'attention fixe a {ctx} avant la trace ONNX")

    vocab = [model.tokenizer.ids_to_tokens([i])[0]
             for i in range(model.tokenizer.vocab_size)]
    n_pua = sum(1 for p in vocab for c in p if 0xE000 <= ord(c) <= 0xF8FF)
    print(f"vocab tete 1 : {len(vocab)} tokens, {n_pua} avec symbole PUA "
          f"(doit etre 0)")
    assert n_pua == 0, "vocabulaire CONTAMINE par des symboles de regles"
    with open(out_vocab, "w", encoding="utf-8") as f:
        json.dump(vocab, f, ensure_ascii=False)
    with open(out_rules, "w", encoding="utf-8") as f:
        json.dump(RULE_CLASSES, f, ensure_ascii=False, indent=2)
    print(f"vocab.json + rules.json ecrits ({N_RULES} classes, PAS de blank -- multi-label)")

    tajwid_head = ConvTajwidHead(model.encoder._feat_out, a.head_hidden, N_RULES)
    tajwid_head.load_state_dict(torch.load(a.head, map_location="cpu"))
    tajwid_head.eval()

    wrapper = DualHeadWrapper(model, tajwid_head)
    wrapper.eval()

    n_mels = model.cfg.preprocessor.features
    dummy_mel = torch.randn(1, n_mels, 200)
    dummy_len = torch.tensor([200], dtype=torch.int64)
    with torch.no_grad():
        ref_l, ref_t = wrapper(dummy_mel, dummy_len)
    print(f"n_mels={n_mels}  lettres{tuple(ref_l.shape)}  tajwid{tuple(ref_t.shape)}")

    torch.onnx.export(
        wrapper,
        (dummy_mel, dummy_len),
        str(out_onnx),
        input_names=["audio_signal", "length"],
        output_names=["logprobs", "tajwid_logprobs"],
        dynamic_axes={
            "audio_signal": {0: "batch", 2: "time"},
            "length": {0: "batch"},
            "logprobs": {0: "batch", 1: "time"},
            "tajwid_logprobs": {0: "batch", 1: "time"},
        },
        opset_version=17,
        do_constant_folding=True,
        dynamo=False,
    )
    print(f"Export : {out_onnx} ({out_onnx.stat().st_size/1e6:.1f} Mo)")

    # ── Validation : le cas ٱلنَّاسِ (114:2) qui a motive ce chantier ──
    import onnxruntime as ort
    import soundfile as sf

    rows = [json.loads(l) for l in
            open(BASE_DIR / "nemo_manifests_dual" / "val_manifest.jsonl",
                 encoding="utf-8")]
    random.seed(2)
    cands = [x for x in rows if x.get("text_tajwid")
             and Path(x["audio_filepath"]).exists()]
    # Prefere un clip 114_2 (ٱلنَّاسِ, le cas ghunnah+laam_shamsiyah simultanes)
    # si present dans le val set ; sinon clip aleatoire comme avant.
    nas_clip = next((x for x in cands if "/114_2.wav" in x["audio_filepath"]), None)
    r = nas_clip or random.choice(cands)
    audio_np, sr = sf.read(r["audio_filepath"], dtype="float32")
    if audio_np.ndim > 1:
        audio_np = audio_np.mean(axis=1)
    audio_t = torch.tensor(audio_np).unsqueeze(0)
    len_t = torch.tensor([audio_np.shape[0]], dtype=torch.int64)
    feats, feats_len = model.preprocessor(input_signal=audio_t, length=len_t)

    with torch.no_grad():
        t_letters, t_tajwid = wrapper(feats, feats_len)
    t_letters, t_tajwid = t_letters.numpy(), t_tajwid.numpy()

    sess = ort.InferenceSession(str(out_onnx), providers=["CPUExecutionProvider"])
    entrees = [i.name for i in sess.get_inputs()]
    print("\nENTREES ONNX :", entrees)
    assert entrees[0] == "audio_signal", "ENTREE INCORRECTE"
    o_letters, o_tajwid = sess.run(
        ["logprobs", "tajwid_logprobs"],
        {"audio_signal": feats.numpy().astype(np.float32),
         "length": feats_len.numpy().astype(np.int64)})

    txt_torch = model.tokenizer.ids_to_text(greedy_letters(t_letters, t_letters.shape[-1] - 1))
    txt_onnx = model.tokenizer.ids_to_text(greedy_letters(o_letters, o_letters.shape[-1] - 1))
    rules_torch = multilabel_rules(t_tajwid)
    rules_onnx = multilabel_rules(o_tajwid)

    print("\n=== Validation (audio_signal/length, multi-label) ===")
    print("CLIP            :", r["audio_filepath"])
    print("TEXTE attendu   :", r["text"][:70])
    print("TETE1 pytorch   :", txt_torch[:70])
    print("TETE1 onnx      :", txt_onnx[:70])
    print("  match tete 1  :", txt_torch.strip() == txt_onnx.strip())
    print("TETE2 pytorch (classes actives, seuil 0.5):", rules_torch)
    print("TETE2 onnx    (classes actives, seuil 0.5):", rules_onnx)
    print("  match tete 2  :", rules_torch == rules_onnx)
    if nas_clip is not None:
        ok = "ghunnah" in rules_torch and "laam_shamsiyah" in rules_torch
        print(f"  ghunnah ET laam_shamsiyah simultanement detectees : {ok}")
    ecart_l = float(np.abs(t_letters - o_letters).max())
    ecart_t = float(np.abs(t_tajwid - o_tajwid).max())
    print(f"  ecart numerique max : lettres={ecart_l:.2e} tajwid={ecart_t:.2e}")
    assert txt_torch.strip() == txt_onnx.strip(), "tete 1 divergente"
    assert rules_torch == rules_onnx, "tete 2 divergente"
    print("\nOK -- pret pour le deploiement.")
    print(f"  dossier : {deploy_dir}")


if __name__ == "__main__":
    main()
