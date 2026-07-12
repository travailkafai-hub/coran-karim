"""
Mini-LoRA personnel (personnalisation vocale, niveau 3 -- cf.
FONCTIONNALITES_FUTURES.md "Personnalisation voix", implemente 2026-07-12 sur
demande explicite malgre les deux inconnues du plan d'origine).

Entree : le .zip exporte depuis l'app (Reglages -> "Mes clips verifies" ->
export) -- contient manifest.jsonl ({clip, text, capturedAt}) + les WAV
correspondants. Ces clips sont des recitations VERIFIEES CORRECTES (session
de reference validee, cf. VoiceLoraClipService/RecitationNotifier) : le texte
associe EST le texte reellement prononce, pas juste le texte canonique visé
(point critique du plan d'origine -- coller le texte canonique sur un audio
fautif reproduirait exactement le biais qu'on corrige par ailleurs avec le
dataset augmente).

Approche : adaptateur NeMo (bottleneck LinearAdapter, cf.
nemo.collections.common.parts.adapter_modules) sur l'encodeur, base ENTIEREMENT
gelee, seul l'adaptateur (quelques dizaines de milliers de parametres)
s'entraine sur le petit volume de clips personnels. Pas besoin d'etape de
"fusion" separee : l'adaptateur fait partie du graphe du modele une fois
attache (model.export() le trace comme le reste) -- meme pipeline d'export
ONNX que benchmark/export_augmented_checkpoint.py.

Usage:
    "D:/Coran Karim/benchmark/.venv/Scripts/python.exe" -X utf8 \
        finetune_fastconformer_lora.py --clips-zip chemin/vers/export.zip
"""
import os, sys, json, argparse, zipfile, wave
os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import torch
import lightning.pytorch as pl
from lightning.pytorch.loggers import CSVLogger
from omegaconf import OmegaConf, open_dict
import nemo.collections.asr as nemo_asr
from nemo.collections.common.parts.adapter_modules import LinearAdapterConfig
from pathlib import Path

BASE_DIR = Path(__file__).parent
BASE_SNAPSHOT = BASE_DIR / "models" / "fastconformer-quran-augmented" / "fastconformer-quran-augmented-snapshot.nemo"
OUT_DIR = BASE_DIR / "models" / "fastconformer-quran-personal"
ADAPTER_NAME = "voice_personal"


class _ZeroRNNTLoss(torch.nn.Module):
    """Meme contournement que finetune_fastconformer.py -- RNNT loss court-
    circuitee (NVVM indisponible sur cette machine), CTC uniquement."""
    def forward(self, log_probs, targets, input_lengths, target_lengths):
        return log_probs.sum() * 0.0


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--clips-zip", type=str, required=True,
                   help="Zip exporte depuis l'app (Reglages -> Mes clips verifies)")
    p.add_argument("--epochs", type=int, default=15,
                   help="Peu de clips -> plus d'epochs que le training principal")
    p.add_argument("--lr", type=float, default=5e-4,
                   help="LR plus eleve que le fine-tune complet (seul l'adaptateur bouge)")
    p.add_argument("--adapter-dim", type=int, default=32,
                   help="Dimension du bottleneck de l'adaptateur")
    p.add_argument("--val-fraction", type=float, default=0.15,
                   help="Fraction des clips reserves a la validation (min 1 clip)")
    return p.parse_args()


def wav_duration_seconds(path: str) -> float:
    with wave.open(path, "rb") as f:
        return f.getnframes() / float(f.getframerate())


def build_personal_manifest(zip_path: str, work_dir: Path) -> tuple[Path, Path]:
    """Extrait le zip, construit train/val manifests NeMo depuis manifest.jsonl."""
    extract_dir = work_dir / "clips"
    extract_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as z:
        z.extractall(extract_dir)

    manifest_src = extract_dir / "manifest.jsonl"
    if not manifest_src.exists():
        raise FileNotFoundError(
            f"manifest.jsonl introuvable dans {zip_path} -- export corrompu ou incomplet ?")

    rows = []
    with open(manifest_src, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            entry = json.loads(line)
            wav_path = extract_dir / entry["clip"]
            if not wav_path.exists():
                print(f"  [WARN] clip manquant, ignore : {entry['clip']}")
                continue
            rows.append({
                "audio_filepath": str(wav_path.resolve()),
                "text": entry["text"],
                "duration": wav_duration_seconds(str(wav_path)),
            })

    if len(rows) < 3:
        raise ValueError(
            f"Seulement {len(rows)} clip(s) exploitable(s) -- volume trop faible pour "
            "un adaptateur utile (le plan d'origine notait déjà ce point comme non "
            "validé empiriquement). Continue à réciter des sessions de référence.")

    print(f"{len(rows)} clips personnels chargés (durée totale "
          f"{sum(r['duration'] for r in rows):.1f}s)")

    import random
    random.seed(0)
    shuffled = rows[:]
    random.shuffle(shuffled)
    n_val = max(1, round(len(shuffled) * 0.15)) if len(shuffled) >= 5 else 0
    val_rows = shuffled[:n_val]
    train_rows = shuffled[n_val:] if n_val else shuffled

    train_path = work_dir / "personal_train.jsonl"
    val_path = work_dir / "personal_val.jsonl"
    with open(train_path, "w", encoding="utf-8") as f:
        for r in train_rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    with open(val_path, "w", encoding="utf-8") as f:
        for r in (val_rows or train_rows[:1]):
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    print(f"  train={len(train_rows)} val={len(val_rows) or 1}")
    return train_path, val_path


def main():
    args = parse_args()
    if not BASE_SNAPSHOT.exists():
        raise FileNotFoundError(
            f"Snapshot de base introuvable : {BASE_SNAPSHOT}\n"
            "Lance d'abord export_augmented_checkpoint.py (modèle actuellement déployé).")

    work_dir = OUT_DIR / "work"
    work_dir.mkdir(parents=True, exist_ok=True)
    train_manifest, val_manifest = build_personal_manifest(args.clips_zip, work_dir)

    print(f"\nChargement du modèle de base (gelé) : {BASE_SNAPSHOT}")
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(BASE_SNAPSHOT), map_location="cpu")
    if hasattr(model, "joint") and hasattr(model.joint, "set_fuse_loss_wer"):
        model.joint.set_fuse_loss_wer(False, loss=None, metric=None)
    model.loss = _ZeroRNNTLoss()
    model.ctc_loss_weight = 1.0

    # ── Adaptateur (cf. docstring module) ────────────────────────────────────
    adapter_cfg = LinearAdapterConfig(
        in_features=model.cfg.encoder.d_model,
        dim=args.adapter_dim,
        dropout=0.0,
    )
    model.add_adapter(name=ADAPTER_NAME, cfg=adapter_cfg)
    model.set_enabled_adapters(name=ADAPTER_NAME, enabled=True)
    model.freeze()  # base ENTIEREMENT gelee
    model.unfreeze_enabled_adapters()  # seul l'adaptateur s'entraine
    n_trainable = sum(p.numel() for p in model.parameters() if p.requires_grad)
    n_total = sum(p.numel() for p in model.parameters())
    print(f"Paramètres entraînables : {n_trainable:,} / {n_total:,} "
          f"({100*n_trainable/n_total:.3f}%)")

    # ── Données ──────────────────────────────────────────────────────────────
    data_cfg_common = dict(
        sample_rate=16000, num_workers=0, pin_memory=True,
        max_duration=30.0, min_duration=0.3, trim_silence=False,
    )
    train_cfg = OmegaConf.create({
        "manifest_filepath": str(train_manifest), "batch_size": 4, "shuffle": True,
        **data_cfg_common,
    })
    val_cfg = OmegaConf.create({
        "manifest_filepath": str(val_manifest), "batch_size": 4, "shuffle": False,
        **data_cfg_common,
    })
    with open_dict(model.cfg):
        model.cfg.train_ds = train_cfg
        model.cfg.validation_ds = val_cfg
        model.cfg.tokenizer.dir = None
        model.cfg.joint.fuse_loss_wer = False
    model.setup_training_data(model.cfg.train_ds)
    model.setup_validation_data(model.cfg.validation_ds)

    optim_cfg = OmegaConf.create({
        "name": "adamw", "lr": args.lr, "betas": [0.9, 0.98], "weight_decay": 1e-4,
        "sched": {"name": "CosineAnnealing", "warmup_steps": 5, "warmup_ratio": None, "min_lr": 1e-6},
    })
    model.setup_optimization(optim_cfg)

    csv_logger = CSVLogger(str(OUT_DIR), name="finetune-personal")
    checkpoint_cb = pl.callbacks.ModelCheckpoint(
        dirpath=str(OUT_DIR), filename="personal-adapter-{epoch:02d}",
        save_top_k=1, monitor="val_wer", mode="min", save_last=True, verbose=True,
    )
    trainer = pl.Trainer(
        max_epochs=args.epochs, accelerator="gpu", devices=1, precision="bf16-mixed",
        gradient_clip_val=1.0, log_every_n_steps=1, val_check_interval=1.0,
        callbacks=[checkpoint_cb], default_root_dir=str(OUT_DIR),
        enable_progress_bar=True, logger=csv_logger,
    )

    print(f"\nDémarrage fine-tune adaptateur : {args.epochs} epochs, lr={args.lr}, "
          f"dim={args.adapter_dim}\n")
    trainer.fit(model)

    out_nemo = OUT_DIR / "fastconformer-quran-personal.nemo"
    model.save_to(str(out_nemo))
    print(f"\nModèle personnel (base gelée + adaptateur) sauvegardé : {out_nemo}")

    # ── Export ONNX (même pipeline que export_augmented_checkpoint.py) ───────
    model.eval()
    onnx_dir = OUT_DIR / "onnx_export"
    onnx_dir.mkdir(parents=True, exist_ok=True)
    onnx_path = onnx_dir / "fastconformer_ctc_personal.onnx"
    model.export(str(onnx_path))
    print(f"Export ONNX terminé : {onnx_path} ({onnx_path.stat().st_size/1e6:.1f} Mo)")
    print("\nÉtape suivante : copier ce .onnx en model.onnx dans le dossier de déploiement "
          "(models/fastconformer-quran-personal/onnx_export/deploy/), en gardant une "
          "sauvegarde du modèle augmenté actuel avant remplacement -- même procédure que "
          "pour le modèle augmenté (cf. mémoire de session).")


if __name__ == "__main__":
    main()
