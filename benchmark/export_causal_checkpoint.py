"""
Export SANS ETAT (memes conventions que export_tajweed_checkpoint.py, cf.
CLAUDE.md piege "audio_signal vs raw_audio") du modele causal entraine cette
session (fastconformer-streaming-causal-v1-lr3e4/causal-final.nemo, 1 seule
tete CTC lettres, PAS la tete tajwid -- demande utilisateur 2026-07-26 :
"dans l'application je teste pas tete tajweed").

Volontairement PAS l'export streaming cache-aware (audio_signal, length,
cache_last_channel, cache_last_time, cache_last_channel_len en entree, cf.
export_streaming_onnx.py) : BufferedTranscriber.kt ne sait pas encore gerer
cet etat entre deux appels (portage Kotlin = etape suivante, non faite). Ce
qu'on teste ICI : est-ce que l'architecture causale (convolutions causales +
contexte droit limite, entrainee) transcrit correctement en un seul appel
(audio_signal/length -> logprobs), donc drop-in compatible avec le plugin
Kotlin actuel SANS modification -- seul le fichier model.onnx change.
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
NEMO_PATH = BASE_DIR / "models" / "fastconformer-streaming-causal-v1-lr3e4" / "causal-final.nemo"
DEPLOY_DIR = BASE_DIR / "models" / "fastconformer-streaming-causal-v1-lr3e4" / "deploy" / "fastconformer-ctc-causal-v1"
OUT_ONNX = DEPLOY_DIR / "model.onnx"
OUT_VOCAB = DEPLOY_DIR / "vocab.json"
VAL_MANIFEST = BASE_DIR / "nemo_manifests_dual" / "val_manifest.jsonl"


class EncCTCWrapper(torch.nn.Module):
    """encoder(audio_signal=mel, length) -> ctc_decoder -> log_softmax.
    Memes noms d'entree que le plugin Kotlin existant (audio_signal/length) :
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
    print("att_context_size effectif :", model.encoder.att_context_size)

    vocab_size = model.tokenizer.vocab_size
    vocab = [model.tokenizer.ids_to_tokens([i])[0] for i in range(vocab_size)]
    with open(OUT_VOCAB, "w", encoding="utf-8") as f:
        json.dump(vocab, f, ensure_ascii=False)
    print(f"vocab.json ecrit : {OUT_VOCAB} ({len(vocab)} tokens)")

    wrapper = EncCTCWrapper(model)
    wrapper.eval()

    n_mels = model.cfg.preprocessor.features
    dummy_mel = torch.randn(1, n_mels, 200)
    dummy_len = torch.tensor([200], dtype=torch.int64)
    with torch.no_grad():
        ref_out = wrapper(dummy_mel, dummy_len)
    print("Shape logprobs (test dummy):", ref_out.shape)

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

    # ── Verification obligatoire (CLAUDE.md) : entrees ONNX = audio_signal ──
    import onnxruntime as ort
    import soundfile as sf

    sess = ort.InferenceSession(str(OUT_ONNX), providers=["CPUExecutionProvider"])
    input_names = [i.name for i in sess.get_inputs()]
    assert "audio_signal" in input_names, f"export inutilisable par l'app: {input_names}"
    print("Entrees ONNX confirmees :", input_names)

    rows = [json.loads(l) for l in open(VAL_MANIFEST, encoding="utf-8")]
    random.seed(2)
    r = random.choice(rows)
    audio_np, sr = sf.read(r["audio_filepath"], dtype="float32")
    audio_t = torch.tensor(audio_np).unsqueeze(0)
    len_t = torch.tensor([audio_np.shape[0]], dtype=torch.int64)
    feats, feats_len = model.preprocessor(input_signal=audio_t, length=len_t)

    with torch.no_grad():
        torch_logprobs = wrapper(feats, feats_len).numpy()

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

    print("\n=== Validation (audio_signal/length, encodeur+CTC seul, causal) ===")
    print("REF       :", r["text"])
    print("PYTORCH   :", txt_torch)
    print("ONNX      :", txt_onnx)
    print("MATCH     :", txt_torch.strip() == txt_onnx.strip())


if __name__ == "__main__":
    main()
