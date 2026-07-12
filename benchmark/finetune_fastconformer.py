"""
Fine-tuning de nvidia/stt_ar_fastconformer_hybrid_large_pc_v1.0 sur le dataset Coran.
Utilise NeMo + PyTorch Lightning.

Usage :
    cd D:/Coran Karim/benchmark
    ../.venv/Scripts/python finetune_fastconformer.py
    # ou avec arguments :
    ../.venv/Scripts/python finetune_fastconformer.py --epochs 10 --batch_size 8
"""
import os, argparse
os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

try:
    import truststore
    truststore.inject_into_ssl()
except ImportError:
    pass

from pathlib import Path
import torch
import lightning.pytorch as pl      # NeMo 2.x utilise lightning (2.4), pas pytorch_lightning (2.6)
from lightning.pytorch.loggers import CSVLogger
from omegaconf import OmegaConf, open_dict
import nemo.collections.asr as nemo_asr
class _ZeroRNNTLoss(torch.nn.Module):
    """Remplace warprnnt_numba/pytorch RNNT par une perte nulle — entraînement CTC uniquement.
    La joint forward (matmul) tourne toujours, mais le DP RNNT O(B*T*U*V) est court-circuité.
    Avec ctc_loss_weight=1.0, la loss totale = 1.0*ctc_loss + 0.0*rnnt_loss = CTC uniquement."""
    def forward(self, log_probs, targets, input_lengths, target_lengths):
        return log_probs.sum() * 0.0  # connecté au graphe autograd, gradient=0


def _restore_ctc_only(nemo_path: str):
    """Charge le modèle et configure entraînement CTC-only (sans numba/NVVM).
    - fuse_loss_wer=False via set_fuse_loss_wer() → joint retourne logits
    - model.loss = _ZeroRNNTLoss() → DP RNNT court-circuité (retour 0 immédiat)
    - model.ctc_loss_weight = 1.0 → loss totale = CTC uniquement
    Résultat: vitesse training normale, CTC head entraîné, RNNT head figé."""
    m = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(nemo_path)
    if hasattr(m, "joint") and hasattr(m.joint, "set_fuse_loss_wer"):
        m.joint.set_fuse_loss_wer(False, loss=None, metric=None)
    m.loss = _ZeroRNNTLoss()
    m.ctc_loss_weight = 1.0
    print("  Mode CTC-only: RNNT loss=ZeroLoss, ctc_loss_weight=1.0 (no numba/NVVM needed)")
    return m

BASE_DIR  = Path(__file__).parent
MANIFEST_DIR = BASE_DIR / "nemo_manifests"
CKPT_DIR  = BASE_DIR / "models" / "fastconformer-quran-pcd"

MODEL_NAME = "nvidia/stt_ar_fastconformer_hybrid_large_pcd_v1.0"  # pcd = +diacritiques (tashkeel), pc n'en a aucun token

def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--epochs",      type=int,   default=10)
    p.add_argument("--batch_size",  type=int,   default=8)
    p.add_argument("--lr",          type=float, default=1e-4)
    p.add_argument("--num_workers", type=int,   default=4)
    p.add_argument("--max_duration",type=float, default=30.0,
                   help="Durée max clip en secondes (clips plus longs ignorés)")
    p.add_argument("--resume",      type=str,   default=None,
                   help="Chemin vers un .nemo (reprise modele) ou .ckpt (reprise training)")
    p.add_argument("--train_manifest", type=str, default=None,
                   help="Override du manifest train (défaut: nemo_manifests/train_manifest.jsonl)")
    p.add_argument("--val_manifest",   type=str, default=None,
                   help="Override du manifest val   (défaut: nemo_manifests/val_manifest.jsonl)")
    p.add_argument("--ckpt_dir",       type=str, default=None,
                   help="Répertoire de sortie des checkpoints (défaut: models/fastconformer-quran-pcd)")
    p.add_argument("--accumulate_grad_batches", type=int, default=4,
                   help="Accumulation de gradient (batch effectif = batch_size * cette valeur)")
    p.add_argument("--tokenizer_dir", type=str, default=None,
                   help="Nouveau tokenizer BPE (dossier avec tokenizer.model) -> change_vocabulary(). "
                        "Requis pour entrainer un vocabulaire different (ex: tajweed).")
    return p.parse_args()

def build_data_config(manifest_path: str, batch_size: int,
                      max_duration: float, num_workers: int,
                      is_train: bool) -> dict:
    return {
        "manifest_filepath": manifest_path,
        "sample_rate": 16000,
        "batch_size": batch_size,
        "shuffle": is_train,
        "num_workers": num_workers,
        "pin_memory": True,
        "max_duration": max_duration,
        "min_duration": 0.5,
        "trim_silence": False,
    }

def main():
    args = parse_args()
    if args.ckpt_dir:
        CKPT_DIR = Path(args.ckpt_dir)
    CKPT_DIR.mkdir(parents=True, exist_ok=True)

    train_manifest = args.train_manifest or str(MANIFEST_DIR / "train_manifest.jsonl")
    val_manifest   = args.val_manifest   or str(MANIFEST_DIR / "val_manifest.jsonl")

    if not Path(train_manifest).exists():
        raise FileNotFoundError(
            f"Manifest introuvable : {train_manifest}\n"
            "Lance d'abord : python prepare_nemo_data.py"
        )

    print(f"Chargement du modèle : {MODEL_NAME}")
    LOCAL_NEMO = BASE_DIR / ".hf" / "nemo_models" / "stt_ar_fastconformer_hybrid_large_pcd_v1.0.nemo"
    ckpt_resume = None  # Pour résumer depuis un .ckpt Lightning

    if args.resume and args.resume.endswith(".ckpt"):
        ckpt_resume = args.resume
        model = _restore_ctc_only(str(LOCAL_NEMO))
        print(f"  Modele: {LOCAL_NEMO.name}, reprise training: {ckpt_resume}")
    elif args.resume and args.resume.endswith(".nemo"):
        model = _restore_ctc_only(args.resume)
        print(f"  Reprise modele .nemo: {args.resume}")
    elif LOCAL_NEMO.exists():
        model = _restore_ctc_only(str(LOCAL_NEMO))
        print(f"  Modele local : {LOCAL_NEMO}")
    else:
        model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.from_pretrained(MODEL_NAME)

    # ── Nouveau vocabulaire (tokenizer tajweed) ───────────────────────────────
    # Le tokenizer pcd d'origine n'a AUCUN token de marque tajweed (wasla, dagger
    # alif, waqf, madda...) car construit sur du texte normalise sans elles ->
    # elles etaient inapprenables (<unk>). change_vocabulary reinitialise la tete
    # CTC (et RNNT) avec le nouveau vocab BPE couvrant tout le tajweed. L'encodeur
    # acoustique (pre-entraine NVIDIA sur arabe general) est CONSERVE intact.
    if args.tokenizer_dir:
        print(f"  change_vocabulary -> {args.tokenizer_dir} (bpe)")
        model.change_vocabulary(new_tokenizer_dir=args.tokenizer_dir, new_tokenizer_type="bpe")
        # Re-appliquer le mode CTC-only apres le changement de vocab (les tetes
        # ont ete recreees ; ctc_loss_weight et la ZeroRNNTLoss doivent persister).
        if hasattr(model, "joint") and hasattr(model.joint, "set_fuse_loss_wer"):
            model.joint.set_fuse_loss_wer(False, loss=None, metric=None)
        model.loss = _ZeroRNNTLoss()
        model.ctc_loss_weight = 1.0

    # ── Données ──────────────────────────────────────────────────────────────
    # Après restore_from(), model.cfg.train_ds.manifest_filepath = ???
    # NeMo accède à self.cfg.train_ds/validation_ds en interne → il faut
    # remplacer ces nœuds via open_dict avant d'appeler setup_*_data.
    train_cfg = build_data_config(
        train_manifest, args.batch_size, args.max_duration,
        args.num_workers, is_train=True
    )
    val_cfg = build_data_config(
        val_manifest, args.batch_size, args.max_duration,
        args.num_workers, is_train=False
    )

    with open_dict(model.cfg):
        model.cfg.train_ds = OmegaConf.create(train_cfg)
        model.cfg.validation_ds = OmegaConf.create(val_cfg)
        model.cfg.test_ds = OmegaConf.create({**val_cfg, "shuffle": False})
        if not args.tokenizer_dir:
            # sans change_vocabulary : neutraliser le chemin tokenizer absolu du
            # .nemo restaure (inexistant ici). AVEC change_vocabulary, le cfg
            # tokenizer pointe deja sur le nouveau dossier -> ne pas l'ecraser.
            model.cfg.tokenizer.dir = None
        model.cfg.joint.fuse_loss_wer = False  # cohérence cfg avec set_fuse_loss_wer()

    model.setup_training_data(model.cfg.train_ds)
    model.setup_validation_data(model.cfg.validation_ds)

    # ── Optimiseur ───────────────────────────────────────────────────────────
    optim_cfg = OmegaConf.create({
        "name": "adamw",
        "lr": args.lr,
        "betas": [0.9, 0.98],
        "weight_decay": 1e-3,
        "sched": {
            "name": "CosineAnnealing",
            "warmup_steps": 500,
            "warmup_ratio": None,
            "min_lr": 1e-6,
        },
    })
    model.setup_optimization(optim_cfg)

    # ── Geler l'encoder les 2 premières epochs (fine-tune CTC head d'abord) ──
    # Optionnel — commenter si GPU suffisant et données assez nombreuses
    # for name, param in model.encoder.named_parameters():
    #     param.requires_grad = False

    # ── Callbacks ────────────────────────────────────────────────────────────
    # monitor val_wer_ctc (metrique CTC reelle), PAS val_wer : en mode CTC-only la
    # tete RNNT est gelee -> son val_wer est du bruit (40-79 ici), inexploitable
    # pour selectionner le meilleur checkpoint (cf. skill model-training/asr.md).
    checkpoint_cb = pl.callbacks.ModelCheckpoint(
        dirpath=str(CKPT_DIR),
        filename="fastconformer-quran-{epoch:02d}-{val_wer_ctc:.3f}",
        monitor="val_wer_ctc",
        mode="min",
        save_top_k=3,
        save_last=True,
        verbose=True,
    )
    # Checkpoint de sécurité toutes les 1000 steps — écrase last.ckpt (pas de monitor)
    periodic_ckpt = pl.callbacks.ModelCheckpoint(
        dirpath=str(CKPT_DIR / "periodic"),
        filename="periodic-last",
        every_n_train_steps=1000,
        save_top_k=0,   # 0 = ne sauvegarder que save_last (pas de ranking par métrique)
        save_last=True,
        verbose=False,
    )
    lr_monitor = pl.callbacks.LearningRateMonitor(logging_interval="step")

    # ── Trainer ──────────────────────────────────────────────────────────────
    # CSVLogger: pas de TensorBoard → pas de conflit protobuf TF/venv sur Windows
    csv_logger = CSVLogger(str(CKPT_DIR), name="finetune-quran")

    trainer = pl.Trainer(
        max_epochs=args.epochs,
        accelerator="gpu",
        devices=1,
        precision="bf16-mixed",
        accumulate_grad_batches=args.accumulate_grad_batches,  # effective batch = batch_size × cette valeur
        gradient_clip_val=1.0,
        log_every_n_steps=50,
        val_check_interval=0.25,            # valider 4× par epoch
        callbacks=[checkpoint_cb, periodic_ckpt, lr_monitor],
        default_root_dir=str(CKPT_DIR),
        enable_progress_bar=True,
        logger=csv_logger,
    )

    print(f"\nDémarrage fine-tune :")
    print(f"  Epochs         : {args.epochs}")
    print(f"  Batch size     : {args.batch_size} × {args.accumulate_grad_batches} grad acc = {args.batch_size * args.accumulate_grad_batches} effectif")
    print(f"  LR             : {args.lr}")
    print(f"  Precision      : bf16-mixed")
    print(f"  Max durée clip : {args.max_duration}s")
    print(f"  Checkpoints    : {CKPT_DIR}\n")

    trainer.fit(model, ckpt_path=ckpt_resume)  # ckpt_resume=None sauf si --resume *.ckpt

    # Sauvegarder en format .nemo
    best_path = CKPT_DIR / "fastconformer-quran-best.nemo"
    model.save_to(str(best_path))
    print(f"\nModèle sauvegardé : {best_path}")

if __name__ == "__main__":
    main()
