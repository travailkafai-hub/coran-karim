#!/usr/bin/env python3
"""
Fine-tune FastConformer CTC (5.8% WER) sur dataset augmenté avec clips TTS.
Objectif: améliorer détection erreurs délibérées (harakat + lettres confusables).

Checkpoint de base: fastconformer-quran-epoch=09-val_wer_ctc=0.058.ckpt (5.8% WER)
Dataset: manifest_augmented.jsonl (251k clips: 233k original + 18k TTS)
"""

import os
os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import torch
import pytorch_lightning as pl
from pathlib import Path

# NeMo
import nemo.collections.asr as nemo_asr
from nemo.core.config import hydra_runner
from nemo.utils import logging

BASE_DIR = Path(__file__).parent
CHECKPOINT = BASE_DIR / "models/fastconformer-quran-tajweed/fastconformer-quran-epoch=09-val_wer_ctc=0.058.ckpt"
MANIFEST_TRAIN = BASE_DIR / "nemo_manifests/train_manifest_augmented.jsonl"
MANIFEST_VAL = BASE_DIR / "nemo_manifests/val_manifest.jsonl"
OUTPUT_DIR = BASE_DIR / "models/fastconformer-quran-tajweed-augmented"

def main():
    print("\n" + "="*80)
    print("🎯 FINE-TUNE FastConformer CTC — Dataset Augmenté (TTS)")
    print("="*80)

    print(f"\n📊 Checkpoint de base: {CHECKPOINT}")
    print(f"   WER actuel: 5.8%")

    print(f"\n📁 Dataset:")
    print(f"   Train: {MANIFEST_TRAIN}")
    print(f"   Val: {MANIFEST_VAL}")

    print(f"\n⚙️  Config fine-tuning:")
    print(f"   Epochs: 2-3")
    print(f"   Batch size: 8 (VRAM limité)")
    print(f"   Accumulation: 4 (effective batch: 32)")
    print(f"   Learning rate: 1e-5 (conservative)")
    print(f"   Output: {OUTPUT_DIR}")

    # Charge checkpoint
    print(f"\n🔄 Chargement checkpoint...")
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(CHECKPOINT))

    # Gèle encodeur (recommandé pour éviter over-fitting sur petits datasets TTS)
    print(f"❄️  Gel encodeur...")
    for param in model.encoder.parameters():
        param.requires_grad = False

    # Force CTC-only (contournement NVVM Windows)
    class _ZeroRNNTLoss(torch.nn.Module):
        def forward(self, log_probs, targets, input_lengths, target_lengths):
            return log_probs.sum() * 0.0

    model.joint.set_fuse_loss_wer(False, loss=None, metric=None)
    model.loss = _ZeroRNNTLoss()
    model.ctc_loss_weight = 1.0

    # Config entraînement
    model.cfg.optim.lr = 1e-5
    model.cfg.optim.sched.warmup_steps = 200
    model.cfg.trainer.max_epochs = 3
    model.cfg.trainer.val_check_interval = 0.5  # Validation 2x par epoch
    model.cfg.trainer.num_sanity_val_steps = 10
    model.cfg.trainer.enable_checkpointing = True
    model.cfg.trainer.checkpoint_callback = True

    # Callbacks
    checkpoint_callback = pl.callbacks.ModelCheckpoint(
        dirpath=str(OUTPUT_DIR),
        filename="fastconformer-quran-augmented-{epoch:02d}-{val_wer_ctc:.3f}",
        monitor="val_wer_ctc",
        mode="min",
        save_top_k=3,
        every_n_train_steps=1000,  # Checkpoint tous les 1000 steps
    )

    early_stopping = pl.callbacks.EarlyStopping(
        monitor="val_wer_ctc",
        mode="min",
        patience=5,
        verbose=True,
    )

    # Trainer
    trainer = pl.Trainer(
        gpus=1,
        max_epochs=model.cfg.trainer.max_epochs,
        val_check_interval=model.cfg.trainer.val_check_interval,
        enable_checkpointing=True,
        callbacks=[checkpoint_callback, early_stopping],
        precision=16,  # mixed precision
        log_every_n_steps=50,
    )

    # Setup data
    print(f"\n📥 Setup données...")
    model.setup_train_data(cfg=model.cfg.train_ds)
    model.setup_validation_data(cfg=model.cfg.validation_ds)

    # Fine-tune
    print(f"\n🚀 Lancement fine-tuning...")
    print(f"   Encoder gelé: OUI")
    print(f"   CTC-only: OUI")
    print(f"   Checkpoint périodique: tous les 1000 steps\n")

    trainer.fit(model)

    # Export meilleur model
    print(f"\n💾 Export meilleur modèle...")
    best_ckpt = sorted(OUTPUT_DIR.glob("*.ckpt"),
                      key=lambda p: float(p.name.split("=")[-1].replace(".ckpt", "")))[-1]
    print(f"   Checkpoint: {best_ckpt}")

    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.load_from_checkpoint(str(best_ckpt))
    export_path = OUTPUT_DIR / "fastconformer-quran-augmented-best.nemo"
    model.save_to(str(export_path))
    print(f"   Exporté: {export_path}")

    print(f"\n✅ Fine-tuning terminé!")
    print(f"   Résultats: {OUTPUT_DIR}")

if __name__ == "__main__":
    main()
