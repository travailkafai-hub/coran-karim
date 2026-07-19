"""
Entrainement HYBRIDE RNNT+CTC de FastConformer — premier run avec la vraie
loss RNNT (NVVM debloque le 2026-07-19, cf. ETAT_CTC_NEMO.md).

Strategie (PLAN_ENTRAINEMENT_HYBRIDE.md §4bis/5) — chaque tete a des besoins
differents, donc DEUX stages au lieu d'un entrainement uniforme :

  --stage 1a : encodeur + tete CTC GELES, seule la branche RNNT (decoder+joint)
               apprend. La tete RNNT est VIERGE (loss ~1041 constatee au smoke
               test) : ses gradients chaotiques du debut ne doivent pas
               traverser l'encodeur warm-starte (acquis mixed-e14, 65% de
               detection d'erreurs — des semaines de travail). LR eleve (tete
               fraiche), rapide (pas de backward encodeur).
               Monitor: val_wer (RNNT — premiere fois que cette metrique est
               REELLE dans ce projet ; en CTC-only elle etait du bruit).

  --stage 1b : degel complet, loss hybride 0.7*RNNT + 0.3*CTC (ponderation
               NVIDIA d'origine, deja dans la config du snapshot). LR bas
               uniforme (5e-5) pour affiner sans detruire.
               Monitor: val_wer_ctc (tete produit primaire).

Base attendue : mixed-e14-snapshot.nemo (meme tokenizer tajweed_bpe_v1 →
PAS de change_vocabulary → la tete CTC garde son acquis, seule RNNT part de 0).

Env requis sur cette machine Ubuntu (cf. CLAUDE.md) :
  SITE=".venv_nemo/lib/python3.14/site-packages"
  CUDA_HOME="$PWD/$SITE/nvidia/cuda_nvcc"   # OBLIGATOIRE pour la loss RNNT
  PYTHONPATH="$PWD/$SITE" /usr/bin/python3.14 finetune_fastconformer_hybrid.py ...
Verifier aussi que le patch local NeMo est present (grep "PATCH LOCAL" dans
nemo/.../cuda_utils/gpu_rnnt_kernel.py — bug numba min/max, cf. ETAT_CTC_NEMO.md).

Usage :
  # Stage 1a (tetes RNNT seules, ~2 epochs)
  python finetune_fastconformer_hybrid.py --stage 1a \
      --init_nemo models/fastconformer-quran-tajweed-mixed/mixed-e14-snapshot.nemo \
      --train_manifest nemo_manifests_mixed/train_mixed_local.jsonl \
      --val_manifest   nemo_manifests_mixed/val_mixed_local.jsonl

  # Stage 1b (degel complet, reprend le resultat de 1a)
  python finetune_fastconformer_hybrid.py --stage 1b \
      --init_nemo models/fastconformer-quran-hybrid-v1/stage1a/stage1a-final.nemo \
      --train_manifest nemo_manifests_mixed/train_mixed_local.jsonl \
      --val_manifest   nemo_manifests_mixed/val_mixed_local.jsonl
"""
import os, argparse
os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

# Python 3.14 : start method par defaut != fork -> les workers du DataLoader
# doivent PICKLER le dataset, et NeMo contient une classe locale non picklable
# (TokenizerWrapper) -> PicklingError. fork n'a pas ce probleme (les workers
# heritent de la memoire, pas de serialisation) et ils ne touchent pas au GPU.
import multiprocessing as _mp
try:
    _mp.set_start_method("fork", force=True)
except RuntimeError:
    pass

from pathlib import Path
import torch
import lightning.pytorch as pl
from lightning.pytorch.loggers import CSVLogger
from omegaconf import OmegaConf, open_dict
import nemo.collections.asr as nemo_asr

BASE_DIR = Path(__file__).parent
OUT_ROOT = BASE_DIR / "models" / "fastconformer-quran-hybrid-v1"

STAGE_DEFAULTS = {
    # LR eleve OK en 1a : seules les tetes fraiches (decoder+joint RNNT)
    # apprennent, l'encodeur gele ne risque rien. ctc_weight 0.5 : encodeur
    # gele -> les tetes n'interagissent pas, le poids n'est qu'une echelle de
    # LR par tete -> equilibre.
    "1a": {"lr": 5e-4, "epochs": 2, "monitor": "val_wer", "ctc_weight": 0.5},
    # LR bas uniforme en 1b (repli documente du plan). ctc_weight 0.7 :
    # INVERSE du defaut NVIDIA (0.3) — decision projet 2026-07-19 : NOTRE tete
    # produit primaire est la CTC (verification, ForcedAligner, karaoke), le
    # RNNT est secondaire (localisation) ; la loss dominante façonne
    # l'encodeur, elle doit servir la CTC d'abord.
    "1b": {"lr": 5e-5, "epochs": 12, "monitor": "val_wer_ctc", "ctc_weight": 0.7},
}


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--stage", required=True, choices=["1a", "1b"])
    p.add_argument("--init_nemo", required=True,
                   help=".nemo de depart (1a: mixed-e14-snapshot ; 1b: stage1a-final)")
    p.add_argument("--train_manifest", required=True)
    p.add_argument("--val_manifest", required=True)
    p.add_argument("--resume_ckpt", default=None,
                   help="Reprise apres crash DANS un stage (periodic/last.ckpt)")
    p.add_argument("--epochs", type=int, default=None)
    p.add_argument("--lr", type=float, default=None)
    p.add_argument("--batch_size", type=int, default=8)
    p.add_argument("--num_workers", type=int, default=8)
    p.add_argument("--max_duration", type=float, default=20.0)
    p.add_argument("--accumulate_grad_batches", type=int, default=4)
    p.add_argument("--ctc_loss_weight", type=float, default=None,
                   help="loss = (1-w)*RNNT + w*CTC. Defaut par stage : 1a=0.5 "
                        "(encodeur gele, poids ~neutre), 1b=0.7 (CTC dominante — "
                        "tete produit primaire de CE projet, inverse du defaut NVIDIA)")
    p.add_argument("--tokenizer_dir", default=None,
                   help="Nouveau tokenizer BPE (ex: regles tajweed) -> change_vocabulary(). "
                        "Reinitialise LES DEUX tetes (CTC et RNNT) ; en 1a la tete CTC "
                        "s'entraine alors aussi (seul l'encodeur reste gele).")
    p.add_argument("--limit_train_batches", type=float, default=1.0,
                   help="<1.0 ou entier : smoke test rapide")
    p.add_argument("--run_tag", default=None,
                   help="Suffixe du dossier de sortie (stage{N}-{tag}) — utile "
                        "pour des runs A/B paralleles (ex: comparer ctc_loss_weight)")
    return p.parse_args()


def build_data_config(manifest_path, batch_size, max_duration, num_workers, is_train):
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
    defaults = STAGE_DEFAULTS[args.stage]
    lr = args.lr if args.lr is not None else defaults["lr"]
    epochs = args.epochs if args.epochs is not None else defaults["epochs"]
    monitor = defaults["monitor"]
    if args.stage == "1a" and args.tokenizer_dir:
        # vocab change -> la tete CTC s'entraine aussi en 1a -> elle redevient
        # la metrique de selection (tete produit primaire)
        monitor = "val_wer_ctc"
    ctc_weight = (args.ctc_loss_weight if args.ctc_loss_weight is not None
                  else defaults["ctc_weight"])

    tag = f"-{args.run_tag}" if args.run_tag else ""
    ckpt_dir = OUT_ROOT / f"stage{args.stage}{tag}"
    ckpt_dir.mkdir(parents=True, exist_ok=True)

    print(f"=== Entrainement hybride RNNT+CTC — stage {args.stage} ===")
    print(f"  init      : {args.init_nemo}")
    print(f"  lr={lr}  epochs={epochs}  monitor={monitor}")
    print(f"  ctc_loss_weight={ctc_weight} (loss = {1-ctc_weight:.1f}*RNNT + {ctc_weight:.1f}*CTC)")
    print(f"  sortie    : {ckpt_dir}")

    # Verifier tot que la loss RNNT est operationnelle (CUDA_HOME + patch NeMo) :
    # mieux vaut echouer ici en 10 s qu'apres le chargement complet du modele.
    from nemo.collections.asr.losses.rnnt import RNNTLoss as _ProbeRNNT
    _probe = _ProbeRNNT(num_classes=9)
    _acts = torch.randn(1, 4, 3, 10, device="cuda", requires_grad=True)
    _loss = _probe(
        log_probs=torch.log_softmax(_acts, dim=-1),
        targets=torch.randint(1, 10, (1, 2)).int().cuda(),
        input_lengths=torch.tensor([4]).int().cuda(),
        target_lengths=torch.tensor([2]).int().cuda(),
    )
    _grad_probe = torch.autograd.grad(_loss.sum(), _acts, allow_unused=True)
    print(f"  probe RNNT loss OK ({float(_loss.sum()):.2f}) — NVVM operationnel")
    del _probe, _acts, _loss, _grad_probe
    torch.cuda.empty_cache()

    # PAS de _ZeroRNNTLoss ici : c'est tout l'objet de ce script. Le snapshot
    # mixed-e14 contient deja la config hybride NVIDIA d'origine
    # (fuse_loss_wer=true, fused_batch_size=4, ctc_loss_weight=0.3) — le mode
    # CTC-only des anciens runs etait un hack runtime jamais sauvegarde.
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(args.init_nemo)

    if args.tokenizer_dir:
        # Nouveau vocabulaire (ex: regles tajweed) : reinitialise LES DEUX tetes
        # (CTC ET decoder/joint RNNT redimensionnes). L'encodeur est conserve.
        print(f"  change_vocabulary -> {args.tokenizer_dir}")
        model.change_vocabulary(new_tokenizer_dir=args.tokenizer_dir,
                                new_tokenizer_type="bpe")
    model.ctc_loss_weight = ctc_weight

    if args.stage == "1a":
        # Encodeur TOUJOURS gele en 1a (proteger le warm-start des gradients
        # chaotiques des tetes fraiches). La tete CTC :
        #   - vocab change -> elle est fraiche aussi -> elle s'entraine en 1a ;
        #   - meme vocab   -> elle est deja bonne -> gelee (seule RNNT apprend).
        model.encoder.freeze()
        if not args.tokenizer_dir:
            model.ctc_decoder.freeze()
        n_train = sum(p.numel() for p in model.parameters() if p.requires_grad)
        n_total = sum(p.numel() for p in model.parameters())
        print(f"  Stage 1a : encodeur GELE"
              + ("" if args.tokenizer_dir else " + ctc_decoder GELE")
              + f" — {n_train/1e6:.1f}M params entrainables / {n_total/1e6:.1f}M")
        assert n_train > 0, "rien a entrainer ?!"
        assert not any(p.requires_grad for p in model.encoder.parameters())
    else:
        # Degel complet (restore_from repart toujours degele, mais expliciter
        # ne coute rien et protege contre un .nemo sauve gele par 1a).
        for p in model.parameters():
            p.requires_grad = True
        model.encoder.unfreeze()
        model.ctc_decoder.unfreeze()
        print("  Stage 1b : tout degele, LR bas uniforme")

    # ── Donnees ──────────────────────────────────────────────────────────────
    train_cfg = build_data_config(args.train_manifest, args.batch_size,
                                  args.max_duration, args.num_workers, True)
    val_cfg = build_data_config(args.val_manifest, args.batch_size,
                                args.max_duration, args.num_workers, False)
    with open_dict(model.cfg):
        model.cfg.train_ds = OmegaConf.create(train_cfg)
        model.cfg.validation_ds = OmegaConf.create(val_cfg)
        model.cfg.test_ds = OmegaConf.create({**val_cfg, "shuffle": False})
    model.setup_training_data(model.cfg.train_ds)
    model.setup_validation_data(model.cfg.validation_ds)

    # ── Optimiseur ───────────────────────────────────────────────────────────
    optim_cfg = OmegaConf.create({
        "name": "adamw",
        "lr": lr,
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

    # ── Callbacks ────────────────────────────────────────────────────────────
    # 1a : monitor val_wer (RNNT, la seule chose qui apprend — val_wer_ctc est
    #      constant, encodeur et tete CTC geles).
    # 1b : monitor val_wer_ctc (tete produit primaire).
    checkpoint_cb = pl.callbacks.ModelCheckpoint(
        dirpath=str(ckpt_dir),
        filename=f"hybrid-s{args.stage}-{{epoch:02d}}-{{{monitor}:.3f}}",
        monitor=monitor,
        mode="min",
        save_top_k=3,
        save_last=True,
        verbose=True,
    )
    periodic_ckpt = pl.callbacks.ModelCheckpoint(
        dirpath=str(ckpt_dir / "periodic"),
        filename="periodic-last",
        every_n_train_steps=1000,
        save_top_k=0,
        save_last=True,
        verbose=False,
    )
    lr_monitor = pl.callbacks.LearningRateMonitor(logging_interval="step")
    csv_logger = CSVLogger(str(ckpt_dir), name="hybrid")

    trainer = pl.Trainer(
        max_epochs=epochs,
        accelerator="gpu",
        devices=1,
        precision="bf16-mixed",
        accumulate_grad_batches=args.accumulate_grad_batches,
        gradient_clip_val=1.0,
        log_every_n_steps=50,
        val_check_interval=0.25,
        limit_train_batches=args.limit_train_batches,
        callbacks=[checkpoint_cb, periodic_ckpt, lr_monitor],
        default_root_dir=str(ckpt_dir),
        enable_progress_bar=True,
        logger=csv_logger,
    )

    print(f"\nDemarrage stage {args.stage} — "
          f"batch {args.batch_size}x{args.accumulate_grad_batches} acc, "
          f"bf16-mixed, max_duration {args.max_duration}s\n", flush=True)
    trainer.fit(model, ckpt_path=args.resume_ckpt)

    # Snapshot .nemo de fin de stage (l'entree du stage suivant / de l'eval).
    final = ckpt_dir / f"stage{args.stage}-final.nemo"
    model.save_to(str(final))
    print(f"\nStage {args.stage} termine — snapshot : {final}")
    if args.stage == "1a":
        print("Prochaine etape : relancer avec --stage 1b "
              f"--init_nemo {final}")


if __name__ == "__main__":
    main()
