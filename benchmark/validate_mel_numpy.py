"""Valide mel_numpy_reference.py contre le vrai preprocesseur NeMo (bit-pres)."""
import os, json, random
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import torch, numpy as np, soundfile as sf
import nemo.collections.asr as nemo_asr
from pathlib import Path
from mel_numpy_reference import compute_mel_features

BASE_DIR = Path(__file__).parent
NEMO_PATH = BASE_DIR / "models" / "fastconformer-quran-pcd" / "fastconformer-quran-pcd-snapshot.nemo"

model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(NEMO_PATH), map_location="cpu")
model.eval()

rows = [json.loads(l) for l in open(BASE_DIR/"nemo_manifests"/"val_manifest.jsonl", encoding="utf-8")]
random.seed(3)
sample = random.sample(rows, 3)

for r in sample:
    audio_np, sr = sf.read(r["audio_filepath"], dtype="float32")
    audio_t = torch.tensor(audio_np).unsqueeze(0)
    len_t = torch.tensor([audio_np.shape[0]])

    with torch.no_grad():
        nemo_feats, nemo_len = model.preprocessor(input_signal=audio_t, length=len_t)
    nemo_feats = nemo_feats[0].numpy()  # (80, T)

    my_feats = compute_mel_features(audio_np)  # (80, T)

    T = min(nemo_feats.shape[1], my_feats.shape[1])
    diff = np.abs(nemo_feats[:, :T] - my_feats[:, :T])
    print(f"clip {r['key'] if 'key' in r else ''}: shape nemo={nemo_feats.shape} mine={my_feats.shape}")
    print(f"  max abs diff={diff.max():.6f}  mean abs diff={diff.mean():.6f}  (echelle normalisee ~[-3,3])")
    print(f"  nemo[0,:5]={nemo_feats[0,:5]}")
    print(f"  mine[0,:5]={my_feats[0,:5]}")
    print()
