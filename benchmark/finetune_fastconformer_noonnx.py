"""
Fine-tuning FastConformer CTC — version sans export ONNX (juste training).
Contourne l'import ONNX qui casse sur protobuf incompatible.
"""
import os
os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import sys
from pathlib import Path

# Bloque l'import ONNX en le blacklistant
sys.modules['onnx'] = None

import torch
import lightning.pytorch as pl
from lightning.pytorch.loggers import CSVLogger
from omegaconf import OmegaConf, open_dict
import nemo.collections.asr as nemo_asr

print("✅ Imports OK (ONNX bloqué)")

class _ZeroRNNTLoss(torch.nn.Module):
    def forward(self, log_probs, targets, input_lengths, target_lengths):
        return log_probs.sum() * 0.0

def _restore_ctc_only(nemo_path: str):
    m = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(nemo_path)
    if hasattr(m, "joint") and hasattr(m.joint, "set_fuse_loss_wer"):
        m.joint.set_fuse_loss_wer(False, loss=None, metric=None)
    m.loss = _ZeroRNNTLoss()
    m.ctc_loss_weight = 1.0
    print("  Mode CTC-only: RNNT loss=ZeroLoss")
    return m

BASE_DIR = Path(__file__).parent
CKPT_DIR = BASE_DIR / "models" / "fastconformer-quran-tajweed-augmented"

CKPT_DIR.mkdir(parents=True, exist_ok=True)

print("\n🎯 FINE-TUNE FastConformer CTC — Dataset Augmenté")
print(f"Checkpoint base: {BASE_DIR / 'models/fastconformer-quran-tajweed/fastconformer-quran-best.nemo'}")
print(f"Train: {BASE_DIR / 'nemo_manifests/train_manifest_augmented_ubuntu.jsonl'}")
print(f"Val:   {BASE_DIR / 'nemo_manifests/val_manifest_ubuntu.jsonl'}")

model = _restore_ctc_only(str(BASE_DIR / "models/fastconformer-quran-tajweed/fastconformer-quran-best.nemo"))

train_cfg = {
    "manifest_filepath": str(BASE_DIR / "nemo_manifests/train_manifest_augmented_ubuntu.jsonl"),
    "sample_rate": 16000,
    "batch_size": 8,
    "shuffle": True,
    "num_workers": 4,
    "pin_memory": True,
    "max_duration": 30.0,
    "min_duration": 0.5,
    "trim_silence": False,
}

val_cfg = {**train_cfg, "shuffle": False, "manifest_filepath": str(BASE_DIR / "nemo_manifests/val_manifest_ubuntu.jsonl")}

with open_dict(model.cfg):
    model.cfg.train_ds = OmegaConf.create(train_cfg)
    model.cfg.validation_ds = OmegaConf.create(val_cfg)
    model.cfg.joint.fuse_loss_wer = False

model.setup_training_data(model.cfg.train_ds)
model.setup_validation_data(model.cfg.validation_ds)

optim_cfg = OmegaConf.create({
    "name": "adamw",
    "lr": 1e-5,
    "betas": [0.9, 0.98],
    "weight_decay": 1e-3,
    "sched": {"name": "CosineAnnealing", "warmup_steps": 500, "min_lr": 1e-6},
})
model.setup_optimization(optim_cfg)

checkpoint_cb = pl.callbacks.ModelCheckpoint(
    dirpath=str(CKPT_DIR),
    filename="fastconformer-quran-augmented-{epoch:02d}-{val_wer_ctc:.3f}",
    monitor="val_wer_ctc",
    mode="min",
    save_top_k=3,
    save_last=True,
)

csv_logger = CSVLogger(str(CKPT_DIR), name="finetune-augmented")

trainer = pl.Trainer(
    max_epochs=2,
    accelerator="gpu",
    devices=1,
    precision="bf16-mixed",
    accumulate_grad_batches=4,
    gradient_clip_val=1.0,
    log_every_n_steps=50,
    val_check_interval=0.25,
    callbacks=[checkpoint_cb],
    default_root_dir=str(CKPT_DIR),
    enable_progress_bar=True,
    logger=csv_logger,
)

print("\n🚀 Lancement fine-tuning...")
trainer.fit(model)

print(f"\n✅ Fine-tuning terminé!")
print(f"Résultats: {CKPT_DIR}")
