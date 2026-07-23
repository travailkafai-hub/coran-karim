import os, sys
sys.stdout.reconfigure(encoding="utf-8")
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import torch
import nemo.collections.asr as nemo_asr
from pathlib import Path

BASE_DIR = Path(__file__).parent
NEMO_PATH = BASE_DIR / "models" / "fastconformer-quran-tajweed-mixed" / "mixed-e14-snapshot.nemo"

# Verites connues (Coran, texte simple sans harakat pour comparaison visuelle rapide)
KNOWN = {
    "036001.wav": "يس",
    "036002.wav": "والقرءان الحكيم",
    "036003.wav": "انك لمن المرسلين",
}

model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(NEMO_PATH), map_location="cpu")
model.eval()
model.cur_decoder = "ctc"

files = [str(BASE_DIR / "data" / "audio" / name) for name in KNOWN]
with torch.no_grad():
    hyps = model.transcribe(files, batch_size=3)
hyps_txt = [h.text if hasattr(h, "text") else h for h in hyps]

print("=== Validation locale epoch14 (audio Ya-Sin 1-3) ===")
for name, hyp in zip(KNOWN, hyps_txt):
    print(f"{name}")
    print(f"  attendu   : {KNOWN[name]}")
    print(f"  reconnu   : {hyp}")
    print()
