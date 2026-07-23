"""Export ONNX du modele A DEUX TETES (2026-07-22) pour le plugin Kotlin.

Modele source : models/fastconformer-dual-head-v1/stagea-long/
    stagea-final.nemo        -> encodeur + tete 1 (lettres+harakat)
    stagea-tajwid-head.pt    -> tete 2 (17 regles tajwid)

Mesures qui ont motive cette architecture (cf. plan) :
    tete tajwid    : rappel 0,90 / precision 0,98 (F1 0,936) sur les 17 classes
    tete lettres   : bit-identique a mixed-e14 (val_letters constant a la 15e
                     decimale sur 15 epochs d'entrainement de la tete 2)
    discrimination : 45% -> 16% de cas ou une variante fautive scorait MIEUX
                     que le mot correct (mesure test_hamwasl_optional_branch)

⚠️ PIEGE DU PROJET, TOMBE DEUX FOIS (2026-07-13 puis 2026-07-19) : l'entree
DOIT s'appeler `audio_signal` (mel deja calcule par MelSpectrogram.kt cote
app), JAMAIS `raw_audio`. Un export "E2E" (preprocessor inclus) valide
pourtant tres bien PyTorch==ONNX mais est INUTILISABLE par l'app : le modele
se charge ("Modele charge : true", rassurant et trompeur) et CHAQUE
transcription echoue en silence avec
    "Unknown input name audio_signal, expected one of [raw_audio, length]"
Ce script part donc de export_rules_260h_checkpoint.py (wrapper encodeur+
decodeurs seuls), jamais d'un *_full_pipeline.py.

── DEUX SORTIES ──
    "logprobs"        (B, T, 1024+1) -- lettres+harakat, INCHANGE
    "tajwid_logprobs" (B, T,   17+1) -- regles tajwid, NOUVEAU
Le nom de la 1ere sortie est conserve a l'identique : un plugin Kotlin qui ne
demande que "logprobs" continue de fonctionner sans modification. Lire la 2e
sortie est un ajout incremental cote app, pas une migration.

Sorties ecrites :
    model.onnx   (les deux tetes, encodeur partage -- un seul passage)
    vocab.json   (1024 tokens de la tete 1, comme avant)
    rules.json   (les 17 noms de classes, dans l'ordre des ids de la tete 2)

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
# 2026-07-23 : stageb-convhead-v1 (degel complet stage B + ConvTajwidHead
# conv1d+MLP au lieu d'une simple couche lineaire) mesure meilleur que tout
# ce qui precede -- F1 tajwid 0.975 (vs 0.953 stagea-long-cont, 0.945
# stagea-long), rappel ikhafa 0.96 / idgham_ghunnah 0.97 (vs 0.87/0.89
# stagea-long-cont). Tete lettres VERIFIEE non degradee (val_wer_ctc=0.1201,
# comparable au 0.1234 historique deploye) malgre le degel complet --
# eval_dual_stats.py. Devient la source de l'export.
# Runs ecartes (gardes sur disque, jamais supprimes) : stagea-augment-*
# (regression mesuree), stageb-v1-cont (LR trop haut, lettres degradee sans
# gain tajwid), stagea-letters-convhead-warmup* (experience decodeur lettres
# plus profond, pas encore concluante -- cf. HANDOFF/memoire du 2026-07-23).
SRC_DIR = BASE_DIR / "models" / "fastconformer-dual-head-v1" / "stageb-convhead-v1"
NEMO_PATH = SRC_DIR / "stageb-final.nemo"
HEAD_PATH = SRC_DIR / "stageb-tajwid-head.pt"
TAJWID_HEAD_HIDDEN = 256  # 0 = nn.Linear (ancien), >0 = ConvTajwidHead
DEPLOY_DIR = (BASE_DIR / "models" / "fastconformer-dual-head-v1" / "deploy"
              / "fastconformer-ctc-dual-head")
OUT_ONNX = DEPLOY_DIR / "model.onnx"
OUT_VOCAB = DEPLOY_DIR / "vocab.json"
OUT_RULES = DEPLOY_DIR / "rules.json"

RULE_CLASSES = [
    "madda_necessary", "madda_obligatory", "madda_permissible", "madda_normal",
    "ghunnah", "ikhafa", "ikhafa_shafawi", "idgham_ghunnah", "idgham_shafawi",
    "iqlab", "idgham_wo_ghunnah", "idgham_mutajanisayn", "idgham_mutaqaribayn",
    "laam_shamsiyah", "ham_wasl", "slnt", "qalaqah",
]
N_RULES = len(RULE_CLASSES)


class DualHeadWrapper(nn.Module):
    """encoder(audio_signal=mel, length) -> DEUX decodeurs sur le MEME
    encodage (un seul passage encodeur, c'est tout l'interet de l'encodeur
    partage). Pas de preprocessor : le mel arrive deja calcule de l'app."""

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
        # encoded est (B, D, T) -> transpose pour la couche lineaire
        tajwid = self.tajwid_head(encoded.transpose(1, 2))
        tajwid = torch.nn.functional.log_softmax(tajwid, dim=-1)
        return letters, tajwid


def greedy(logprobs, blank_id):
    ids = logprobs[0].argmax(axis=-1)
    out, prev = [], None
    for i in ids:
        if i != prev and i != blank_id:
            out.append(int(i))
        prev = i
    return out


def main():
    DEPLOY_DIR.mkdir(parents=True, exist_ok=True)
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        str(NEMO_PATH), map_location="cpu")
    model.eval()
    model.preprocessor.featurizer.dither = 0.0

    # ── Garde-fou : le vocabulaire de la tete 1 ne doit contenir AUCUN
    # symbole de regle. S'il y en a, on exporte un modele issu de la mauvaise
    # lignee (rules-260h/piste3/piste4) et tout le benefice de la separation
    # des tetes est perdu.
    vocab = [model.tokenizer.ids_to_tokens([i])[0]
             for i in range(model.tokenizer.vocab_size)]
    n_pua = sum(1 for p in vocab for c in p if 0xE000 <= ord(c) <= 0xF8FF)
    print(f"vocab tete 1 : {len(vocab)} tokens, {n_pua} avec symbole PUA "
          f"(doit etre 0)")
    assert n_pua == 0, ("vocabulaire CONTAMINE par des symboles de regles -- "
                        "ce n'est pas un modele 2 tetes issu de mixed-e14")
    with open(OUT_VOCAB, "w", encoding="utf-8") as f:
        json.dump(vocab, f, ensure_ascii=False)
    with open(OUT_RULES, "w", encoding="utf-8") as f:
        json.dump(RULE_CLASSES, f, ensure_ascii=False, indent=2)
    print(f"vocab.json + rules.json ecrits ({N_RULES} classes, blank={N_RULES})")

    if TAJWID_HEAD_HIDDEN > 0:
        tajwid_head = ConvTajwidHead(model.encoder._feat_out,
                                      TAJWID_HEAD_HIDDEN, N_RULES + 1)
    else:
        tajwid_head = nn.Linear(model.encoder._feat_out, N_RULES + 1)
    tajwid_head.load_state_dict(torch.load(HEAD_PATH, map_location="cpu"))
    tajwid_head.eval()

    wrapper = DualHeadWrapper(model, tajwid_head)
    wrapper.eval()

    n_mels = model.cfg.preprocessor.features
    dummy_mel = torch.randn(1, n_mels, 200)
    dummy_len = torch.tensor([200], dtype=torch.int64)
    with torch.no_grad():
        ref_l, ref_t = wrapper(dummy_mel, dummy_len)
    print(f"n_mels={n_mels}  lettres{tuple(ref_l.shape)}  "
          f"tajwid{tuple(ref_t.shape)}")

    torch.onnx.export(
        wrapper,
        (dummy_mel, dummy_len),
        str(OUT_ONNX),
        input_names=["audio_signal", "length"],
        # "logprobs" garde son nom EXACT : compatibilite avec le plugin actuel.
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
    print(f"Export : {OUT_ONNX} ({OUT_ONNX.stat().st_size/1e6:.1f} Mo)")

    # ── Validation sur un VRAI clip annote (pas seulement du bruit) ──
    import onnxruntime as ort
    import soundfile as sf

    rows = [json.loads(l) for l in
            open(BASE_DIR / "nemo_manifests_dual" / "val_manifest.jsonl",
                 encoding="utf-8")]
    random.seed(2)
    cands = [x for x in rows if x.get("text_tajwid")
             and Path(x["audio_filepath"]).exists()]
    r = random.choice(cands)
    audio_np, sr = sf.read(r["audio_filepath"], dtype="float32")
    if audio_np.ndim > 1:
        audio_np = audio_np.mean(axis=1)
    audio_t = torch.tensor(audio_np).unsqueeze(0)
    len_t = torch.tensor([audio_np.shape[0]], dtype=torch.int64)
    feats, feats_len = model.preprocessor(input_signal=audio_t, length=len_t)

    with torch.no_grad():
        t_letters, t_tajwid = wrapper(feats, feats_len)
    t_letters, t_tajwid = t_letters.numpy(), t_tajwid.numpy()

    sess = ort.InferenceSession(str(OUT_ONNX),
                                providers=["CPUExecutionProvider"])
    entrees = [i.name for i in sess.get_inputs()]
    print("\nENTREES ONNX :", entrees)
    assert entrees[0] == "audio_signal", (
        "ENTREE INCORRECTE -- l'app enverra audio_signal et echouera en "
        "silence sur CHAQUE transcription (piege documente)")
    o_letters, o_tajwid = sess.run(
        ["logprobs", "tajwid_logprobs"],
        {"audio_signal": feats.numpy().astype(np.float32),
         "length": feats_len.numpy().astype(np.int64)})

    txt_torch = model.tokenizer.ids_to_text(
        greedy(t_letters, t_letters.shape[-1] - 1))
    txt_onnx = model.tokenizer.ids_to_text(
        greedy(o_letters, o_letters.shape[-1] - 1))
    rules_torch = [RULE_CLASSES[i] for i in greedy(t_tajwid, N_RULES)]
    rules_onnx = [RULE_CLASSES[i] for i in greedy(o_tajwid, N_RULES)]
    attendu = [RULE_CLASSES[ord(c) - 0xE000] for c in r["text_tajwid"]]

    print("\n=== Validation (audio_signal/length, 2 tetes) ===")
    print("TEXTE attendu   :", r["text"][:70])
    print("TETE1 pytorch   :", txt_torch[:70])
    print("TETE1 onnx      :", txt_onnx[:70])
    print("  match tete 1  :", txt_torch.strip() == txt_onnx.strip())
    print("REGLES attendues:", attendu)
    print("TETE2 pytorch   :", rules_torch)
    print("TETE2 onnx      :", rules_onnx)
    print("  match tete 2  :", rules_torch == rules_onnx)
    ecart_l = float(np.abs(t_letters - o_letters).max())
    ecart_t = float(np.abs(t_tajwid - o_tajwid).max())
    print(f"  ecart numerique max : lettres={ecart_l:.2e} tajwid={ecart_t:.2e}")
    assert txt_torch.strip() == txt_onnx.strip(), "tete 1 divergente"
    assert rules_torch == rules_onnx, "tete 2 divergente"
    print("\nOK -- pret pour le deploiement.")
    print(f"  dossier : {DEPLOY_DIR}")


if __name__ == "__main__":
    main()
