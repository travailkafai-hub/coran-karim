"""
Export CORRECT du modele hybride "vrai tajweed" stage1b-260h pour le plugin
Kotlin (FastConformerCtc.kt attend {"audio_signal": mel_features, "length"} ->
encodeur+decodeur CTC seulement, PAS le pipeline E2E audio-brut).

Modele source : models/fastconformer-quran-hybrid-v1/stage1b-260h/stage1b-final.nemo
(meilleure version mesuree, cf. PLAN_ENTRAINEMENT_HYBRIDE.md 5ter : CER
canonique 6.85% vs 9.18% deploye, corrections silencieuses 10.7% vs 14.7%,
+ 17 regles tajwid en symboles PUA U+E000..U+E010).

PIEGE DEJA DOCUMENTE, REPRODUIT UNE 2e FOIS LE 2026-07-19 : j'ai d'abord
ecrit export_rules_260h_full_pipeline.py en copiant
export_tajweed_full_pipeline.py (wrapper E2E raw_audio+length ->
preprocessor+encoder+ctc). Ca valide bien PyTorch==ONNX, mais le plugin
Kotlin calcule le mel LUI-MEME (MelSpectrogram.kt) et envoie
audio_signal=mel. Resultat sur device : le modele "charge" (true) mais
CHAQUE transcription echoue en silence avec
  "[BufferedTranscriber] echec retranscription: Unknown input name
   audio_signal, expected one of [raw_audio, length]"
=> aucune transcription, aucun suivi, aucune coloration. Exactement l'erreur
que l'en-tete de export_tajweed_checkpoint.py decrivait deja (correction du
2026-07-13). Ne JAMAIS repartir de *_full_pipeline.py pour un export destine
a l'app : partir de ce fichier ou de export_tajweed_checkpoint.py.

Verification rapide avant tout deploiement (doit afficher audio_signal) :
  python3 -c "import onnxruntime as ort; \
    print([i.name for i in ort.InferenceSession('<model.onnx>').get_inputs()])"

word_tokens.json NON genere (meme decision que l'export tajweed : l'app
retombe sur la tokenisation greedy de CtcTokenizer.kt, qui gere les symboles
PUA comme n'importe quelle piece du vocabulaire).
"""
import os, json, random
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import torch, numpy as np
import nemo.collections.asr as nemo_asr
from pathlib import Path

BASE_DIR = Path(__file__).parent
NEMO_PATH = BASE_DIR / "models" / "fastconformer-quran-hybrid-v1" / "stage1b-260h" / "stage1b-final.nemo"
DEPLOY_DIR = BASE_DIR / "models" / "fastconformer-quran-hybrid-v1" / "deploy" / "fastconformer-ctc-rules-260h"
OUT_ONNX = DEPLOY_DIR / "model.onnx"
OUT_VOCAB = DEPLOY_DIR / "vocab.json"


class EncCTCWrapper(torch.nn.Module):
    """encoder(audio_signal=mel, length) -> ctc_decoder -> log_softmax.
    Memes noms d'entree que le plugin Kotlin (audio_signal/length) :
    PAS de preprocessor ici, le mel est deja calcule cote app."""
    def __init__(self, model):
        super().__init__()
        self.encoder = model.encoder
        self.ctc_decoder = model.ctc_decoder

    def forward(self, audio_signal: torch.Tensor, length: torch.Tensor):
        encoded, encoded_len = self.encoder(audio_signal=audio_signal, length=length)
        logits = self.ctc_decoder(encoder_output=encoded)
        return torch.nn.functional.log_softmax(logits, dim=-1)


def main():
    DEPLOY_DIR.mkdir(parents=True, exist_ok=True)
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(NEMO_PATH), map_location="cpu")
    model.eval()
    model.preprocessor.featurizer.dither = 0.0

    vocab_size = model.tokenizer.vocab_size
    vocab = [model.tokenizer.ids_to_tokens([i])[0] for i in range(vocab_size)]
    with open(OUT_VOCAB, "w", encoding="utf-8") as f:
        json.dump(vocab, f, ensure_ascii=False)
    n_pua = sum(1 for p in vocab for c in p if 0xE000 <= ord(c) <= 0xF8FF)
    print(f"vocab.json ecrit : {OUT_VOCAB} ({len(vocab)} tokens, "
          f"{n_pua} pieces contenant un symbole de regle)")

    wrapper = EncCTCWrapper(model)
    wrapper.eval()

    n_mels = model.cfg.preprocessor.features
    dummy_mel = torch.randn(1, n_mels, 200)
    dummy_len = torch.tensor([200], dtype=torch.int64)
    with torch.no_grad():
        ref_out = wrapper(dummy_mel, dummy_len)
    print(f"n_mels={n_mels} — shape logprobs (dummy):", ref_out.shape)

    torch.onnx.export(
        wrapper,
        (dummy_mel, dummy_len),
        str(OUT_ONNX),
        input_names=["audio_signal", "length"],
        output_names=["logprobs"],
        dynamic_axes={
            "audio_signal": {0: "batch", 2: "time"},
            "length": {0: "batch"},
            "logprobs": {0: "batch", 1: "time"},
        },
        opset_version=17,
        do_constant_folding=True,
        dynamo=False,
    )
    print(f"Export termine : {OUT_ONNX} ({OUT_ONNX.stat().st_size/1e6:.1f} Mo)")

    # ── Validation : ONNX (audio_signal/length) vs PyTorch, sur un vrai clip ──
    import onnxruntime as ort
    import soundfile as sf

    rows = [json.loads(l) for l in open(BASE_DIR / "nemo_manifests_rules" / "val_manifest.jsonl", encoding="utf-8")]
    random.seed(2)
    # Clip contenant au moins un symbole de regle : verifie aussi que les
    # symboles ressortent bien du decodage greedy ONNX.
    r = random.choice([x for x in rows if any(0xE000 <= ord(c) <= 0xF8FF for c in x["text"])])
    audio_np, sr = sf.read(r["audio_filepath"], dtype="float32")
    audio_t = torch.tensor(audio_np).unsqueeze(0)
    len_t = torch.tensor([audio_np.shape[0]], dtype=torch.int64)
    feats, feats_len = model.preprocessor(input_signal=audio_t, length=len_t)

    with torch.no_grad():
        torch_logprobs = wrapper(feats, feats_len).numpy()

    sess = ort.InferenceSession(str(OUT_ONNX), providers=["CPUExecutionProvider"])
    print("ENTREES ONNX :", [i.name for i in sess.get_inputs()])
    onnx_logprobs = sess.run(["logprobs"], {
        "audio_signal": feats.numpy().astype(np.float32),
        "length": feats_len.numpy().astype(np.int64),
    })[0]

    def greedy_decode(logprobs, tokenizer, blank_id):
        ids = logprobs[0].argmax(axis=-1)
        out, prev = [], None
        for i in ids:
            if i != prev and i != blank_id:
                out.append(int(i))
            prev = i
        return tokenizer.ids_to_text(out)

    blank_id = torch_logprobs.shape[-1] - 1
    txt_torch = greedy_decode(torch_logprobs, model.tokenizer, blank_id)
    txt_onnx = greedy_decode(onnx_logprobs, model.tokenizer, blank_id)

    def show(t):
        return "".join(f"<U+{ord(c):04X}>" if 0xE000 <= ord(c) <= 0xF8FF else c for c in t)

    print("\n=== Validation (audio_signal/length, encodeur+CTC seul) ===")
    print("REF       :", show(r["text"]))
    print("PYTORCH   :", show(txt_torch))
    print("ONNX      :", show(txt_onnx))
    print("MATCH     :", txt_torch.strip() == txt_onnx.strip())
    print("SYMBOLES DE REGLES EMIS PAR ONNX :",
          any(0xE000 <= ord(c) <= 0xF8FF for c in txt_onnx))


if __name__ == "__main__":
    main()
