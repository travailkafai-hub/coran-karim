"""Fine-tune CTC de l'encodeur Nemotron 3.5 (cache-aware pre-entraine) + tete
CTC fraiche sur notre vocabulaire (cf. make_nemotron_ctc_init.py pour le
POURQUOI complet et la genealogie).

Contrairement a finetune_streaming_causal.py :
  - PAS de tete RNNT a neutraliser -- ce modele (EncDecCTCModelBPE) n'en a
    jamais eu, donc pas de warprnnt_numba/NVVM/CUDA_HOME nulle part.
  - Encodeur NON GELE des le depart (lecon 2026-07-24 : le geler perd l'acquis
    de calibration fine, cf. stagea-multilabel-v1 dans ETAT_CTC_NEMO.md) --
    mais LR plus bas que d'habitude car l'encodeur est pre-entraine, pas
    initialise a chaud depuis notre propre checkpoint.
  - `att_context_size` DEJA multi-lookahead cache-aware de fabrique
    ([[56,3],[56,0],[56,6],[56,13]]) -- on le GARDE tel quel (c'est batit pour
    ca), on ne le fige pas a une seule valeur comme on l'a fait pour notre
    propre causalisation.

⚠️ Tourne dans .venv_nemotron_ft (Python 3.13 + NeMo main 3.1.0), PAS
.venv_nemo (Python 3.14 + NeMo 2.5.0, qui reste la chaine de reference).

USAGE
  ./.venv_nemotron_ft/bin/python3.13 benchmark/finetune_nemotron_ctc.py
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"

import argparse
from pathlib import Path

import torch.multiprocessing as _mp
try:
    _mp.set_start_method("fork", force=True)
except RuntimeError:
    pass

import lightning.pytorch as pl
from lightning.pytorch.loggers import CSVLogger
from omegaconf import OmegaConf, open_dict
import nemo.collections.asr as nemo_asr

BASE = Path(__file__).parent
MANIFESTS = BASE / "nemo_manifests_dual"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--init_nemo", default=str(BASE / "models/nemotron-ctc-init.nemo"))
    p.add_argument("--train_manifest", default=str(MANIFESTS / "train_manifest.jsonl"))
    p.add_argument("--val_manifest", default=str(MANIFESTS / "val_manifest.jsonl"))
    p.add_argument("--out", default=str(BASE / "models/nemotron-ctc-v1"))
    p.add_argument("--epochs", type=int, default=6)
    p.add_argument("--resume_from", default=None)
    p.add_argument("--save_top_k", type=int, default=3)
    p.add_argument("--batch_size", type=int, default=8)
    p.add_argument("--accumulate_grad_batches", type=int, default=4)
    # LR plus bas que nos runs habituels (1e-4) : l'encodeur est 5x plus gros
    # et pre-entraine sur un objectif different (RNNT multilingue) -- on veut
    # l'adapter au coranique en douceur, pas ecraser sa calibration cache-aware.
    p.add_argument("--lr", type=float, default=3e-5)
    p.add_argument("--val_check_interval", type=float, default=0.25)
    args = p.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    print(f"init : {args.init_nemo}")
    model = nemo_asr.models.EncDecCTCModelBPE.restore_from(
        args.init_nemo, map_location="cpu")
    e = model.cfg.encoder
    print(f"encodeur : d_model={e.d_model} att_context_size={e.get('att_context_size')} "
          f"causal_downsampling={e.get('causal_downsampling')}")
    if hasattr(model, "wer"):
        model.wer.log_prediction = False

    def data_cfg(path, is_train):
        return {
            "manifest_filepath": path, "sample_rate": 16000,
            "batch_size": args.batch_size, "shuffle": is_train,
            "num_workers": 6, "pin_memory": True,
            "max_duration": 20.0, "min_duration": 0.5,
            "is_tarred": False, "use_start_end_token": False,
        }

    with open_dict(model.cfg):
        model.cfg.train_ds = OmegaConf.create(data_cfg(args.train_manifest, True))
        model.cfg.validation_ds = OmegaConf.create(data_cfg(args.val_manifest, False))
        model.cfg.test_ds = OmegaConf.create(data_cfg(args.val_manifest, False))
    model.setup_training_data(model.cfg.train_ds)
    model.setup_validation_data(model.cfg.validation_ds)

    model.cfg.optim = OmegaConf.create({
        "name": "adamw", "lr": args.lr, "betas": [0.9, 0.98], "weight_decay": 1e-3,
        "sched": {"name": "CosineAnnealing", "warmup_steps": 1000, "min_lr": 1e-6},
    })
    model.setup_optimization(model.cfg.optim)

    # Checkpoint intermediaire obligatoire (regle du skill model-training) :
    # aucun filet en dehors de ce que le script sauvegarde lui-meme.
    ckpt = pl.callbacks.ModelCheckpoint(
        dirpath=str(out), filename="nemotron-ctc-{epoch:02d}-{step:06d}-{val_wer:.3f}",
        monitor="val_wer", mode="min", save_top_k=args.save_top_k, save_last=True)

    trainer = pl.Trainer(
        max_epochs=args.epochs, accelerator="gpu", devices=1,
        precision="bf16-mixed",
        accumulate_grad_batches=args.accumulate_grad_batches,
        val_check_interval=args.val_check_interval,
        callbacks=[ckpt, pl.callbacks.LearningRateMonitor("step")],
        logger=CSVLogger(str(out), name="logs"),
        log_every_n_steps=50, enable_progress_bar=True,
    )
    print(f"epochs={args.epochs} batch={args.batch_size} "
          f"accum={args.accumulate_grad_batches} lr={args.lr}")
    if args.resume_from:
        print(f"REPRISE depuis : {args.resume_from}")
    trainer.fit(model, ckpt_path=args.resume_from)

    final = out / "nemotron-ctc-final.nemo"
    model.save_to(str(final))
    print(f"ecrit : {final}")


if __name__ == "__main__":
    main()
