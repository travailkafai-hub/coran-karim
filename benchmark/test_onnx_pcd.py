"""
Valide que l'ONNX exporte (fastconformer_ctc_pcd.onnx) produit bien le meme
texte que le modele NeMo natif -- test du pipeline complet (checkpoint -> onnx ->
inference pure onnxruntime, sans PyTorch/NeMo a l'execution) avant integration mobile.
"""
import os, json, random
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import torch, numpy as np, onnxruntime as ort
import nemo.collections.asr as nemo_asr
from pathlib import Path

BASE_DIR = Path(__file__).parent
NEMO_PATH = BASE_DIR / "models" / "fastconformer-quran-pcd" / "fastconformer-quran-pcd-snapshot.nemo"
ONNX_PATH = BASE_DIR / "models" / "fastconformer-quran-pcd" / "onnx_export" / "fastconformer_ctc_pcd.onnx"

model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(NEMO_PATH), map_location="cpu")
model.eval()

rows = [json.loads(l) for l in open(BASE_DIR/"nemo_manifests"/"val_manifest.jsonl", encoding="utf-8")]
random.seed(1)
sample = random.sample(rows, 3)

sess = ort.InferenceSession(str(ONNX_PATH), providers=["CPUExecutionProvider"])
tokenizer = model.tokenizer

for r in sample:
    wav_path = r["audio_filepath"]
    ref = r["text"]

    # Preprocess exactement comme NeMo (meme mel-spectrogram, meme normalisation)
    audio, sr = torch.tensor([]), 16000
    import soundfile as sf
    audio_np, sr = sf.read(wav_path, dtype="float32")
    audio_t = torch.tensor(audio_np).unsqueeze(0)
    length_t = torch.tensor([audio_np.shape[0]])
    feats, feats_len = model.preprocessor(input_signal=audio_t, length=length_t)

    # ── Inference ONNX pur ──────────────────────────────────────────────────
    ort_inputs = {
        "audio_signal": feats.numpy().astype(np.float32),
        "length": feats_len.numpy().astype(np.int64),
    }
    logprobs = sess.run(["logprobs"], ort_inputs)[0]  # (B, T, V)
    ids = logprobs[0].argmax(axis=-1)

    # CTC greedy decode (collapse repeats + blank=vocab_size-1 pour NeMo BPE CTC)
    blank_id = logprobs.shape[-1] - 1
    collapsed = []
    prev = None
    for i in ids:
        if i != prev and i != blank_id:
            collapsed.append(int(i))
        prev = i
    onnx_text = tokenizer.ids_to_text(collapsed)

    # ── Inference NeMo native (reference) ───────────────────────────────────
    model.cur_decoder = "ctc"
    with torch.no_grad():
        native_hyp = model.transcribe([wav_path], batch_size=1)[0]
    native_text = native_hyp.text if hasattr(native_hyp, "text") else native_hyp

    print("REF  :", ref)
    print("NEMO :", native_text)
    print("ONNX :", onnx_text)
    print("MATCH:", onnx_text.strip() == native_text.strip())
    print()
