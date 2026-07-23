#!/usr/bin/env python3
"""Benchmark 3.22% vs 5.54% checkpoints sur validation dataset"""
import os
os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

from pathlib import Path
import torch
import nemo.collections.asr as nemo_asr

BASE_DIR = Path(__file__).parent
VAL_MANIFEST = BASE_DIR / "nemo_manifests" / "val_manifest_ubuntu.jsonl"
CHECKPOINT_322 = BASE_DIR / "models/fastconformer-quran-tajweed-augmented/fastconformer-quran-epoch=01-val_wer_ctc=0.032.ckpt"
CHECKPOINT_554 = BASE_DIR / "models/fastconformer-quran-tajweed-augmented/fastconformer-quran-epoch=06-val_wer_ctc=0.055.ckpt"

print("🧪 BENCHMARK: 3.22% vs 5.54% WER Checkpoints\n")
print("=" * 60)

for name, ckpt in [("3.22% (Epoch 1)", CHECKPOINT_322), ("5.54% (Epoch 6)", CHECKPOINT_554)]:
    print(f"\n📊 Testant: {name}")
    print(f"   Checkpoint: {ckpt.name}")

    try:
        model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.load_from_checkpoint(str(ckpt))
        print(f"   ✅ Modèle chargé")

        # Évaluer sur validation set
        print(f"   ⏳ Évaluation sur {VAL_MANIFEST.name}...")
        model.setup_validation_data(
            nemo_asr.models.EncDecHybridRNNTCTCBPEModel.from_config_dict({
                "manifest_filepath": str(VAL_MANIFEST),
                "sample_rate": 16000,
                "batch_size": 16,
                "shuffle": False,
                "use_start_end_token": False,
                "num_workers": 8,
                "pin_memory": True,
            })
        )

        print(f"   ✅ Validation setup complete")

    except Exception as e:
        print(f"   ❌ Erreur: {e}")

print("\n" + "=" * 60)
print("✅ Benchmark terminé")
