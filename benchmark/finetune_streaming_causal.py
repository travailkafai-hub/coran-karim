"""STAGE 1 du fine-tune STREAMING — adaptation causale de l'encodeur.

CONTEXTE (2026-07-25). L'app fait de l'ASR d'enonce complet EN BOUCLE pour
simuler du streaming : un segment de 7 s est retranscrit a 1, 3, 4, 6 et 7 s,
soit 21 s d'audio traitees pour 7 s de parole. Toutes les pathologies mesurees
sur device en decoulent (derive de normalisation, syllabes doublees, texte
`entendu` instable d'une passe a l'autre). Le calcul n'est PAS le goulot
(12-15 % CPU) : c'est l'architecture. Le vrai streaming exige des convolutions
CAUSALES, ce que le checkpoint actuel n'a jamais appris.

⚠️ NE PAS retenter une bascule par la seule configuration : essayee QUATRE fois
(test_streaming_ctc.py, test_official_stream_step.py, export_streaming_onnx.py,
simulate_kotlin_streaming.py) et impossible par construction -- cf.
references/asr.md du skill model-training.

STAGE 0 (deja fait, cf. make_causal_init.py) : 706 des 707 tenseurs transferes
tels quels ; seul `encoder.pre_encode.out.weight` change de forme
([512,2560] -> [512,2816], 10 -> 11 bandes de frequence) et est recopie bande a
bande avec la nouvelle a zero. Depart a chaud, pas une reinitialisation.
Chemin de production valide : ONNX stateful exporte, etat propage sur 3 chunks.

CE QUE FAIT CE SCRIPT
  - repart de `streaming-causal-init.nemo` ;
  - entraine l'encodeur + la tete CTC lettres (la tete tajwid n'existe pas
    encore a ce stade : elle est rattachee au STAGE 2 via finetune_dual_head.py,
    dont le protocole gel/degel est deja eprouve) ;
  - RNNT neutralise (`_ZeroRNNTLoss`), comme tous les runs de ce projet :
    l'app n'utilise QUE le CTC (GOP, ForcedAligner, karaoke).

MULTI-LOOKAHEAD (doctrine NVIDIA)
`att_context_size` accepte une LISTE : le modele est entraine sur tous les
contextes et la latence se choisit A L'INFERENCE, sans reentrainer.
Formule officielle : look-ahead(s) = att_context_size[1] * subsampling * stride
                                   = R * 8 * 0,01 = R * 80 ms
  [70,13] -> 1,04 s (defaut NVIDIA)   [70,6] -> 480 ms   [70,1] -> 80 ms
⛔ Le commentaire d'origine d'export_streaming_onnx.py annoncait "[70,1] ~1120ms,
le plus gros preset" : FAUX, corrige sur place. C'est le plus AGRESSIF.

USAGE
  SITE="benchmark/.venv_nemo/lib/python3.14/site-packages"
  PYTHONPATH="$PWD/$SITE" /usr/bin/python3.14 benchmark/finetune_streaming_causal.py
"""
import os
os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import argparse
from pathlib import Path

import torch
import torch.multiprocessing as _mp
# Python 3.14 a change la methode de demarrage par defaut des sous-processus
# sur Linux (`fork` -> `forkserver`), qui impose de SERIALISER les objets passes
# aux workers. Le dataset BPE de NeMo definit `TokenizerWrapper` comme classe
# LOCALE dans `AudioToBPEDataset.__init__` -> `PicklingError: Can't pickle local
# object`, et le training meurt au sanity check. `fork` retablit le
# comportement des runs precedents de ce projet.
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


class _ZeroRNNTLoss(torch.nn.Module):
    """Neutralise la branche RNNT : l'app n'utilise que le CTC, et le RNNT est
    le composant le moins mature du projet (pas de DP d'alignement force simple,
    auto-regressif donc pas frame-synchrone). Meme choix que les runs mixed-e14
    et dual-head."""
    def forward(self, *a, **k):
        return torch.tensor(0.0, requires_grad=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--init_nemo", default=str(BASE / "models/streaming-causal-init.nemo"))
    p.add_argument("--train_manifest", default=str(MANIFESTS / "train_manifest.jsonl"))
    p.add_argument("--val_manifest", default=str(MANIFESTS / "val_manifest.jsonl"))
    p.add_argument("--out", default=str(BASE / "models/fastconformer-streaming-causal-v1"))
    p.add_argument("--epochs", type=int, default=4)
    # Reprise apres crash (2026-07-25) : un Xid 8 (RC watchdog GPU, declenche
    # par l'extinction PHYSIQUE de l'ecran pendant un entrainement -- le
    # moniteur envoie un DPMS off au GPU qui sert aussi l'affichage, et un
    # noyau CUDA en cours peut se faire tuer comme "fige") a interrompu la
    # premiere tentative a l'epoch 3/4. Le GPU redevient sain immediatement
    # (verifie : calcul test reussi juste apres), seul le PROCESSUS meurt.
    # `--resume_from` restaure modele + optimiseur + planificateur + compteur
    # d'epoch via `trainer.fit(ckpt_path=...)` -- une reprise ne recommence pas
    # a zero. Ne PAS eteindre l'ecran physique pendant qu'un training tourne
    # sur ce GPU ; persistence mode et reglages GNOME ne previennent pas ce cas
    # (verifie : deja actifs au moment du crash).
    p.add_argument("--resume_from", default=None)
    # Distinct de --resume_from : ne charge QUE les POIDS (pas l'optimiseur ni
    # le planificateur LR), pour redemarrer l'optimisation a neuf -- avec un LR
    # different -- sans repartir de zero sur les poids. Necessaire des le
    # 2026-07-25 : deux strategies de contexte differentes (multi-lookahead
    # PUIS fixe [70,13]) ont plateauve a la MEME valeur (~0,49-0,51), ce qui
    # refute l'hypothese "bruit du multi-lookahead" et pointe vers un LR trop
    # bas (1e-4) pour sortir de ce plateau -- `--resume_from` aurait restaure
    # l'etat Adam/scheduler d'ORIGINE et annule tout changement de --lr.
    p.add_argument("--init_weights_from", default=None)
    p.add_argument("--save_top_k", type=int, default=5)
    p.add_argument("--augment_silence", action="store_true",
                   help="insere des pauses internes dans le train (cf. "
                        "causal_silence_augment.py) -- vise l'ecart mesure sur "
                        "la recitation hesitante")
    p.add_argument("--silence_prob", type=float, default=0.5,
                   help="fraction des clips augmentes. <1 volontairement : le "
                        "regime fluide est deja a parite, on l'AJOUTE a "
                        "l'hesitant au lieu de l'echanger contre lui")
    # Contexte(s) d'attention. Par defaut : le SEUL [70,13] (1,04s, defaut
    # NVIDIA), pas le multi-lookahead -- corrige le 2026-07-25 apres un
    # plateau observe (val_wer_ctc bloque a ~0,50 sur ~1,5 epoch, `0,502 ->
    # 0,509 -> 0,502 -> 0,506 -> 0,502 -> 0,506 -> 0,503 -> 0,500 -> 0,501`,
    # aucune amelioration malgre 3 epochs supplementaires). Hypothese : tirer
    # un contexte DIFFERENT a chaque pas (donc une architecture effective
    # differente -- fenetre d'attention et padding causal changeants) rend le
    # signal d'optimisation plus bruite qu'un entrainement a contexte FIXE,
    # ce qui ralentit la reeducation des convolutions causales. Strategie
    # retenue : converger d'abord sur le contexte le mieux documente, la
    # multi-lookahead sera reintroduite en fine-tuning une fois la base
    # solide -- pas abandonnee, juste reordonnee.
    p.add_argument("--contexts", default="70,13",
                    help="ex. '70,13' (fixe) ou '70,13;70,6;70,1' (multi-lookahead)")
    p.add_argument("--val_wer_ctc_target", type=float, default=0.20,
                    help="objectif indicatif -- reference offline non-causale : 0,124")
    p.add_argument("--batch_size", type=int, default=8)
    p.add_argument("--accumulate_grad_batches", type=int, default=4)
    # LR BAS : le 5.0 + NoamAnnealing de la config NVIDIA vaut pour un
    # entrainement DEPUIS ZERO. Ici on part d'un modele deja bon en offline, on
    # ne veut pas detruire l'acquis en reapprenant la causalite.
    p.add_argument("--lr", type=float, default=1e-4)
    p.add_argument("--val_check_interval", type=float, default=0.25)
    args = p.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    print(f"init      : {args.init_nemo}")
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        args.init_nemo, map_location="cpu")
    if args.init_weights_from:
        print(f"POIDS SEULS charges depuis : {args.init_weights_from} "
              f"(optimiseur/scheduler repartent a neuf avec --lr={args.lr})")
        src = Path(args.init_weights_from)
        # BUG CORRIGE (2026-07-26) : un `.nemo` est une ARCHIVE TAR (config +
        # poids + tokenizer, cf. make_causal_init.py), PAS un `.ckpt` Lightning
        # brut. `torch.load()` dessus plantait immediatement
        # (`KeyError: filename 'storages' not found`, torch essaie de le lire
        # comme un vieux format de checkpoint pytorch). Constate : ce crash
        # (code 1) survenait AVANT tout entrainement -> aucun checkpoint
        # jamais ecrit -> le superviseur, ne trouvant rien a reprendre,
        # relancait SANS --init_weights_from -> tout un cycle a tourne sur
        # l'init causal D'ORIGINE au lieu du resultat du cycle precedent,
        # silencieusement, pendant des heures.
        if src.suffix == ".nemo":
            src_model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
                str(src), map_location="cpu")
            model.load_state_dict(src_model.state_dict(), strict=True)
        else:
            ck = torch.load(str(src), map_location="cpu", weights_only=False)
            model.load_state_dict(ck.get("state_dict", ck), strict=True)

    e = model.cfg.encoder
    print(f"encodeur  : att_context_style={e.get('att_context_style')} "
          f"conv_context_size={e.get('conv_context_size')} "
          f"causal_downsampling={e.get('causal_downsampling')}")

    # ── Contexte(s) d'attention : fixe par defaut, multi sur demande ───────
    contexts = [[int(x) for x in c.split(",")] for c in args.contexts.split(";")]
    model.encoder.set_default_att_context_size(contexts[0])
    with open_dict(model.cfg):
        model.cfg.encoder.att_context_size = contexts
    if hasattr(model.encoder, "att_context_size_all"):
        model.encoder.att_context_size_all = contexts
    # En multi-lookahead, NeMo TIRE AU SORT un contexte a chaque pas
    # d'entrainement via `random.choices(att_context_size_all, att_context_probs)`.
    # Ces probabilites sont calculees a la CONSTRUCTION de l'encodeur, a partir
    # du `att_context_size` d'origine (une seule entree ici) : muter la liste
    # apres coup sans les regenerer donne
    # `ValueError: The number of weights does not match the population`
    # des le premier pas. On les remet donc en coherence, uniformement.
    probs = [1.0 / len(contexts)] * len(contexts)
    for attr in ("att_context_probs", "att_context_size_all"):
        if hasattr(model.encoder, attr):
            setattr(model.encoder, attr,
                    probs if attr == "att_context_probs" else contexts)
    with open_dict(model.cfg):
        model.cfg.encoder.att_context_probs = probs
    print(f"contextes : {contexts}  probs={probs}")
    for c in contexts:
        print(f"            {c} -> look-ahead {c[1]*8*10}ms")

    model.loss = _ZeroRNNTLoss()
    if hasattr(model, "wer"):
        model.wer.log_prediction = False

    # ── Augmentation par pauses INTERNES (2026-07-26) ────────────────────
    # Cible l'ecart MESURE sur le regime hesitant : +13 pt de WER contre
    # l'offline (79,4 % vs 66,2 %, `simulate_sliding_window.py --n 30`), alors
    # que le regime fluide est deja a parite. Cf. causal_silence_augment.py
    # pour le POURQUOI complet et les deux choix de conception.
    #
    # ⚠️ NE JAMAIS porter cette augmentation dans `finetune_dual_head.py` :
    # ce script-la utilise des cibles tajwid au niveau FRAME
    # (`--train_frame_spans`), calculees sur les timings de l'audio D'ORIGINE.
    # Inserer du silence decale toutes les frames suivantes -> les etiquettes
    # tajwid deviennent fausses SILENCIEUSEMENT (aucune erreur, le modele
    # apprend juste une mauvaise association). Ici c'est sur : le CTC est sans
    # alignement, le silence est absorbe en blank et la transcription de
    # reference est inchangee.
    augmentor = None
    if args.augment_silence:
        import causal_silence_augment
        causal_silence_augment.register()
        augmentor = {
            "internal_silence": {
                "prob": args.silence_prob,
                "min_pause_secs": 0.5, "max_pause_secs": 2.5,
                "min_pauses": 1, "max_pauses": 3,
            }
        }
        print(f"augmentation pauses internes ACTIVE (prob={args.silence_prob}) "
              f"-- uniquement sur le train, jamais sur la validation")

    def data_cfg(path, is_train):
        cfg = {
            "manifest_filepath": path, "sample_rate": 16000,
            "batch_size": args.batch_size, "shuffle": is_train,
            "num_workers": 6, "pin_memory": True,
            "max_duration": 20.0, "min_duration": 0.5,
            "is_tarred": False, "use_start_end_token": False,
        }
        # Validation JAMAIS augmentee : sa comparabilite avec les runs
        # precedents est ce qui rend `val_wer_ctc` lisible d'un run a l'autre.
        # L'effet sur l'hesitant se mesure separement au banc segmente.
        if is_train and augmentor is not None:
            cfg["augmentor"] = augmentor
        # max_duration s'applique APRES l'augmentation : jusqu'a 3 pauses de
        # 2,5 s peuvent ajouter 7,5 s. Sans marge, les clips longs augmentes
        # seraient filtres et l'augmentation ne porterait plus que sur les
        # clips courts -- biais invisible.
        if is_train and augmentor is not None:
            cfg["max_duration"] = 20.0 + 3 * 2.5
        return cfg

    with open_dict(model.cfg):
        model.cfg.train_ds = OmegaConf.create(data_cfg(args.train_manifest, True))
        model.cfg.validation_ds = OmegaConf.create(data_cfg(args.val_manifest, False))
        # `test_ds` doit etre renseigne meme si on ne teste jamais : la config du
        # .nemo le porte a `???` (valeur obligatoire manquante) et NeMo y accede
        # pendant setup -> MissingMandatoryValue. On le pointe sur la validation.
        model.cfg.test_ds = OmegaConf.create(data_cfg(args.val_manifest, False))
    model.setup_training_data(model.cfg.train_ds)
    model.setup_validation_data(model.cfg.validation_ds)

    model.cfg.optim = OmegaConf.create({
        "name": "adamw", "lr": args.lr, "betas": [0.9, 0.98], "weight_decay": 1e-3,
        "sched": {"name": "CosineAnnealing", "warmup_steps": 1000, "min_lr": 1e-6},
    })
    model.setup_optimization(model.cfg.optim)

    # ── Checkpoint intermediaire OBLIGATOIRE (regle du skill) ─────────────
    # Un run de plusieurs heures n'a AUCUN filet ici : ni cluster, ni
    # orchestrateur. On sauvegarde 4 fois par epoch, pas seulement a la fin.
    # `save_top_k` BORNE (2026-07-25, corrige apres coup) : `-1` (tout garder)
    # a ete tente en premier sur demande utilisateur (« garde toujours des
    # checkpoints qu'on peut tester et reutiliser ») mais chaque checkpoint
    # fait ~1,4 Go et le disque (68 Go libres, ~15 Go/h a ce rythme) aurait
    # plante le run par manque d'espace BIEN avant convergence -- pire que de
    # perdre des checkpoints intermediaires. `save_top_k=5` + `save_last=True`
    # garde les 5 meilleurs (par val_wer_ctc) + le plus recent : largement
    # assez pour tester/reprendre, sans croissance illimitee. Le HDD n'etant
    # pas monte, impossible d'archiver les anciens plutot que les ecraser --
    # a faire des qu'il sera disponible (regle du projet : deplacer, jamais
    # supprimer un run qui pourrait servir).
    ckpt = pl.callbacks.ModelCheckpoint(
        dirpath=str(out), filename="causal-{epoch:02d}-{step:06d}-{val_wer_ctc:.3f}",
        monitor="val_wer_ctc", mode="min", save_top_k=args.save_top_k, save_last=True)

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
    print(f"validation toutes les {args.val_check_interval} epoch -> checkpoint")
    if args.resume_from:
        print(f"REPRISE depuis : {args.resume_from}")
    trainer.fit(model, ckpt_path=args.resume_from)

    final = out / "causal-final.nemo"
    model.save_to(str(final))
    print(f"ecrit : {final}")
    # Un `.nemo` est directement rechargeable et exportable en ONNX, contrairement
    # a un `.ckpt` Lightning qui exige l'architecture de reference. On en produit
    # donc un a la fin de chaque run, en plus des checkpoints par validation.


if __name__ == "__main__":
    main()
