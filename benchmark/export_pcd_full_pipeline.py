"""
Exporte pipeline COMPLETE (audio brut 16kHz -> logprobs CTC) en un seul graphe ONNX,
pour eviter de re-implementer le calcul mel-spectrogramme (FFT + filtrage) en Dart/Kotlin
cote mobile -- risque d'erreurs numeriques subtiles qui degraderaient le WER.

Entree ONNX : raw_audio (1, num_samples) float32, length (1,) int64 [nb echantillons]
Sortie ONNX : logprobs (1, T, 1025) float32 (log-softmax, CTC blank = index 1024)

Usage mobile ensuite : juste argmax + collapse-repeats + detokenisation BPE (simple),
plus besoin de FFT/mel cote app.
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
NEMO_PATH = BASE_DIR / "models" / "fastconformer-quran-pcd" / "fastconformer-quran-pcd-snapshot.nemo"
OUT_ONNX = BASE_DIR / "models" / "fastconformer-quran-pcd" / "onnx_export" / "fastconformer_ctc_pcd_e2e.onnx"


class E2ECTCWrapper(torch.nn.Module):
    """preprocessor(raw audio) -> encoder -> ctc_decoder -> log_softmax, en un seul graphe."""
    def __init__(self, model):
        super().__init__()
        self.preprocessor = model.preprocessor
        self.encoder = model.encoder
        self.ctc_decoder = model.ctc_decoder

    def forward(self, raw_audio: torch.Tensor, length: torch.Tensor):
        feats, feats_len = self.preprocessor(input_signal=raw_audio, length=length)
        encoded, encoded_len = self.encoder(audio_signal=feats, length=feats_len)
        logits = self.ctc_decoder(encoder_output=encoded)
        logprobs = torch.nn.functional.log_softmax(logits, dim=-1)
        return logprobs


def main():
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(NEMO_PATH), map_location="cpu")
    model.eval()
    # dither doit etre desactive en inference pure (sinon bruit aleatoire injecte a chaque appel)
    model.preprocessor.featurizer.dither = 0.0

    wrapper = E2ECTCWrapper(model)
    wrapper.eval()

    dummy_audio = torch.randn(1, 32000)   # 2s @ 16kHz
    dummy_len = torch.tensor([32000], dtype=torch.int64)

    with torch.no_grad():
        ref_out = wrapper(dummy_audio, dummy_len)
    print("Shape logprobs (test dummy):", ref_out.shape)

    torch.onnx.export(
        wrapper,
        (dummy_audio, dummy_len),
        str(OUT_ONNX),
        input_names=["raw_audio", "length"],
        output_names=["logprobs"],
        dynamic_axes={
            "raw_audio": {0: "batch", 1: "num_samples"},
            "length": {0: "batch"},
            "logprobs": {0: "batch", 1: "time"},
        },
        opset_version=17,
        do_constant_folding=True,
        dynamo=False,   # l'exporteur dynamo (torch.export) echoue sur le control-flow
                        # data-dependent de normalize_batch (seq_len==1) -> legacy TorchScript tracer
    )
    print(f"Export E2E termine : {OUT_ONNX} ({OUT_ONNX.stat().st_size/1e6:.1f} Mo)")

    # ── Validation : comparer sortie ONNX vs PyTorch sur un vrai clip ────────
    import onnxruntime as ort
    import soundfile as sf

    rows = [json.loads(l) for l in open(BASE_DIR/"nemo_manifests"/"val_manifest.jsonl", encoding="utf-8")]
    random.seed(2)
    r = random.choice(rows)
    audio_np, sr = sf.read(r["audio_filepath"], dtype="float32")
    audio_t = torch.tensor(audio_np).unsqueeze(0)
    len_t = torch.tensor([audio_np.shape[0]], dtype=torch.int64)

    with torch.no_grad():
        torch_logprobs = wrapper(audio_t, len_t).numpy()

    sess = ort.InferenceSession(str(OUT_ONNX), providers=["CPUExecutionProvider"])
    onnx_logprobs = sess.run(["logprobs"], {
        "raw_audio": audio_t.numpy().astype(np.float32),
        "length": len_t.numpy().astype(np.int64),
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
    txt_onnx  = greedy_decode(onnx_logprobs, model.tokenizer, blank_id)

    print("\n=== Validation pipeline E2E (raw audio -> ONNX) ===")
    print("REF       :", r["text"])
    print("PYTORCH   :", txt_torch)
    print("ONNX E2E  :", txt_onnx)
    print("MATCH     :", txt_torch.strip() == txt_onnx.strip())
    print("Max diff logprobs:", float(np.max(np.abs(torch_logprobs[:, :onnx_logprobs.shape[1]] - onnx_logprobs[:, :torch_logprobs.shape[1]]))) if torch_logprobs.shape[1]==onnx_logprobs.shape[1] else "shape mismatch")


if __name__ == "__main__":
    main()
