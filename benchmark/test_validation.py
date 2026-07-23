#!/usr/bin/env python3
"""Validate both checkpoints on val_manifest_ubuntu.jsonl"""
import os
os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

from pathlib import Path
import nemo.collections.asr as nemo_asr
from omegaconf import OmegaConf, open_dict

BASE_DIR = Path(__file__).parent
VAL_MANIFEST = BASE_DIR / "nemo_manifests" / "val_manifest_ubuntu.jsonl"
CHECKPOINT_322 = BASE_DIR / "models/fastconformer-quran-tajweed-augmented/fastconformer-quran-epoch=01-val_wer_ctc=0.032.ckpt"
CHECKPOINT_554 = BASE_DIR / "models/fastconformer-quran-tajweed-augmented/fastconformer-quran-epoch=06-val_wer_ctc=0.055.ckpt"

print("\n🧪 BENCHMARK: Checkpoint Validation\n")
print("=" * 70)

results = {}

for name, ckpt_path in [("3.22% (Epoch 1)", CHECKPOINT_322), ("5.54% (Epoch 6)", CHECKPOINT_554)]:
    print(f"\n📊 Testing: {name}")
    print(f"   File: {ckpt_path.name}")

    try:
        model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.load_from_checkpoint(str(ckpt_path), map_location="cpu")
        print(f"   ✅ Model loaded (CPU)")

        with open_dict(model.cfg):
            model.cfg.validation_ds.manifest_filepath = str(VAL_MANIFEST)
            model.cfg.validation_ds.batch_size = 16
            model.cfg.validation_ds.num_workers = 4

        model.setup_validation_data(model.cfg.validation_ds)
        print(f"   ✅ Validation dataset setup")

        results[name] = "✅ Ready for validation"

    except Exception as e:
        results[name] = f"❌ Error: {str(e)[:60]}"
        print(f"   ❌ {str(e)[:80]}")

print("\n" + "=" * 70)
print("\n📋 SUMMARY:")
for name, status in results.items():
    print(f"   {name}: {status}")
print("\n✅ Test complete")
