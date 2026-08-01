"""Entrainement A DEUX TETES CTC sur encodeur partage (2026-07-22).

    encodeur partage
      ├─ tete 1 (CTC) : lettres + harakat  -- vocabulaire mixed-e14, 1024 BPE
      └─ tete 2 (CTC) : regles tajwid      -- 17 classes + blank, PAS de BPE

── POURQUOI (mesures de cette session, cf. plan) ──
Melanger lettres et symboles de regles dans UN vocabulaire cause deux degats :
  1. ~20% de masse de probabilite part sur les tokens-symboles meme sur un mot
     SANS regle attendue (mesure sur "يَوْمِ" : gop -0,03 -> -20,09).
  2. Le symbole ham_wasl casse la fusion BPE `ٱ+ل` : le modele n'apprend
     jamais le token soude `▁ٱلْعَ` sur de l'audio coranique (1,6% des lignes
     annotees) alors que c'est celui que l'alignement force lui reclame.
Deux softmax separes suppriment les deux par construction.

── POURQUOI PAS DE RNNT ──
L'app n'utilise QUE le CTC (GOP, ForcedAligner, karaoke). Le RNNT n'a pas de
DP d'alignement force simple (auto-regressif, pas frame-synchrone) et c'est le
composant le moins mature du projet. Il est donc neutralise ici
(`_ZeroRNNTLoss`, comme les runs mixed-e14 d'origine).

── POURQUOI PARTIR DE mixed-e14 ──
Verifie le 2026-07-22 : son tokenizer contient 1024 tokens et ZERO symbole PUA
-- c'est EXACTEMENT le vocabulaire dont la tete 1 a besoin. Aucun
`change_vocabulary` n'est donc necessaire : la tete CTC lettres garde tous ses
poids (val_wer_ctc 0,124) au lieu de repartir de zero. Ce sont les pistes
2/3/4 qui changeaient de tokenizer et reinitialisaient cette tete.

── PROTOCOLE 2 ETAPES ──
  --stage a : encodeur + tete 1 GELES. Seule la tete 2 (fraiche, gradients
              chaotiques au debut) apprend. Protege l'acquis de mixed-e14.
  --stage b : degel complet, loss = w1*CTC_lettres + w2*CTC_tajwid, LR bas.

── MASQUAGE DE LA LOSS TAJWID ──
98 280 des 156 892 clips (ASC arabe general, TTS) n'ont AUCUNE annotation
tajwid. Leur imposer une cible vide apprendrait a la tete 2 a se taire sur ces
voix -- information fausse ("non annote" != "aucune regle"). Ces clips sont
donc EXCLUS de la loss tajwid (masque) tout en entrainant normalement la
tete 1.

Usage :
  SITE=".venv_nemo/lib/python3.14/site-packages"
  PYTHONPATH="$PWD/$SITE" /usr/bin/python3.14 finetune_dual_head.py --stage a \
      --init_nemo models/fastconformer-quran-tajweed-mixed/mixed-e14-snapshot.nemo
"""
import os, json, argparse
os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

from pathlib import Path
import torch
import torch.nn as nn
import torch.nn.functional as F
import lightning.pytorch as pl
from lightning.pytorch.loggers import CSVLogger
from omegaconf import OmegaConf, open_dict
import nemo.collections.asr as nemo_asr

BASE_DIR = Path(__file__).parent
OUT_ROOT = BASE_DIR / "models" / "fastconformer-dual-head-v1"
MANIFEST_DIR = BASE_DIR / "nemo_manifests_dual"

# 17 classes de regles (ordre = build_rules_annotated_corpus.py, symboles
# U+E000..U+E010). Ce sont les seules sorties de la tete 2 : AUCUNE lettre,
# AUCUNE harakat -- c'est toute la raison d'etre de la separation. Pas de BPE
# non plus : une classification par frame, pas une tokenisation de texte.
# AJOUT waqf_lazim/waqf_awla (2026-07-24, decision utilisateur -- cf.
# FONCTIONNALITES_FUTURES.md §9) : positions deja connues via
# app/assets/data/quran_waqf.json, fenetre = silence REEL detecte juste apres
# le mot (cf. build_frame_level_tajwid_labels.py::waqf_span_after). Les 5
# autres types (jaiz/wasl_awla/mamnu/muanaqah/sakta) restent hors-perimetre :
# mamnu en particulier demanderait de detecter une ABSENCE de regle, signal
# different, pas traite ici.
RULE_CLASSES = [
    "madda_necessary", "madda_obligatory", "madda_permissible", "madda_normal",
    "ghunnah", "ikhafa", "ikhafa_shafawi", "idgham_ghunnah", "idgham_shafawi",
    "iqlab", "idgham_wo_ghunnah", "idgham_mutajanisayn", "idgham_mutaqaribayn",
    "laam_shamsiyah", "ham_wasl", "slnt", "qalaqah",
    "waqf_lazim", "waqf_awla",
]
N_RULES = len(RULE_CLASSES)          # 19 -> ids 0..18


class _ZeroRNNTLoss(nn.Module):
    """Neutralise la branche RNNT (cf. docstring) sans la retirer du modele --
    meme mecanisme que les runs mixed-e14 d'origine."""

    def forward(self, log_probs, targets, input_lengths, target_lengths):
        return log_probs.sum() * 0.0


def load_frame_spans_lookup(spans_jsonl_path):
    """chemin audio -> (n_frames, [[class_id, start_frame, end_frame_incl], ...]).

    Remplace load_tajwid_lookup/tajwid_ids (2026-07-24) : l'ancienne cible
    etait une SEQUENCE ORDONNEE de symboles consommee par F.ctc_loss (une
    seule classe gagnante par frame, ordre impose) -- structurellement
    incapable de representer deux regles VRAIMENT simultanees (mesure device :
    laam_shamsiyah et ghunnah sur les MEMES frames dans "ٱلنَّاسِ", l'un
    n'etant jamais detecte car l'autre gagne le softmax). Les fenetres par
    classe, independantes, permettent le chevauchement par construction --
    cf. build_frame_level_tajwid_labels.py pour comment elles sont derivees
    (alignement force de la tete 1, deja fiable, val_wer_ctc=0.124)."""
    lut = {}
    for line in open(spans_jsonl_path, encoding="utf-8"):
        r = json.loads(line)
        lut[r["audio_filepath"]] = (r["n_frames"], r["spans"])
    return lut


class ConvTajwidHead(nn.Module):
    """Tete 2 plus profonde (2026-07-23, objectif val_tajwid<0.1 sans degrader
    la tete lettres) : une seule couche lineaire plafonnait a ~0,125 en stage
    b meme a LR tres bas (5e-5 puis 1e-5 -- la loss ne bougeait plus, ce n'etait
    donc pas un probleme d'optimisation mais de CAPACITE). Un conv1d temporel
    (contexte des frames voisines, utile pour des regles qui sont des
    TRANSITIONS -- qalqala/idgham/madd) suivi d'une petite MLP donne de la
    marge sans changer la nature de la tache (classification par frame,
    toujours pas de BPE/modelisation de langue)."""

    def __init__(self, d, hidden, n_out, kernel=5):
        super().__init__()
        self.conv = nn.Conv1d(d, hidden, kernel_size=kernel, padding=kernel // 2)
        self.act = nn.GELU()
        self.drop = nn.Dropout(0.1)
        self.out = nn.Linear(hidden, n_out)

    def forward(self, x):  # x: (B, T, D) -- meme contrat que nn.Linear avant
        h = self.conv(x.transpose(1, 2)).transpose(1, 2)
        h = self.drop(self.act(h))
        return self.out(h)


class ConvLettersDecoder(nn.Module):
    """Remplacement du decodeur CTC lettres natif de NeMo (2026-07-23,
    tentative -- PRUDENCE : cf. le precedent documente dans
    BENCHMARK_RESULTS.md ou un val_wer_ctc interne tres bas (0,032) masquait
    un WER reel de 28-44% hors studio -- ne JAMAIS conclure sur ce seul
    chiffre pour cette tete, revalider sur audio reel avant de faire confiance
    a un gain).

    Le decodeur natif (`ConvASRDecoder`) est un simple Conv1d(kernel_size=1)
    -- verifie le 2026-07-23, strictement equivalent a une couche lineaire,
    AUCUN contexte temporel. Meme limite de capacite que l'ancienne tete
    tajwid avant ConvTajwidHead. Interface IDENTIQUE a ConvASRDecoder.forward
    (entree (B,C,T), sortie (B,T,vocab+1) en LOG-PROBS) pour rester un
    remplacement direct, sans toucher au reste du script."""

    def __init__(self, d, hidden, vocab_size, kernel=5):
        super().__init__()
        self.conv = nn.Conv1d(d, hidden, kernel_size=kernel, padding=kernel // 2)
        self.act = nn.GELU()
        self.drop = nn.Dropout(0.1)
        self.out = nn.Conv1d(hidden, vocab_size + 1, kernel_size=1)

    def forward(self, encoder_output):  # (B, C, T) -- comme ConvASRDecoder
        h = self.drop(self.act(self.conv(encoder_output)))
        logits = self.out(h).transpose(1, 2)  # (B, T, vocab+1)
        return torch.nn.functional.log_softmax(logits, dim=-1)


class DualHeadTrainer(pl.LightningModule):
    """Encodeur + tete CTC lettres (NeMo, reutilises tels quels) + tete CTC
    tajwid (neuve). N'herite PAS du modele NeMo : on veut un controle total du
    training_step, sans interaction cachee avec la machinerie RNNT."""

    def __init__(self, nemo_model, tajwid_by_index, stage, lr,
                 w_letters, w_tajwid, head_hidden=0,
                 train_letters_in_stage_a=False, pos_weight=None):
        super().__init__()
        self.m = nemo_model
        # index collection -> (n_frames, [[class_id, start, end_incl], ...])
        # (2026-07-24, cf. load_frame_spans_lookup -- avant : liste d'ids
        # ORDONNEE pour F.ctc_loss)
        self.tajwid_by_index = tajwid_by_index
        self.stage = stage
        self.lr = lr
        self.w_letters = w_letters
        self.w_tajwid = w_tajwid
        # Poids par classe (2026-07-24, idee utilisateur : attenuer l'impact
        # des classes tres frequentes dans la loss BCE) -- optionnel, cf.
        # calibrate_tajwid_pos_weight.py. None = tout a 1.0 (comportement par
        # defaut si non fourni).
        self.register_buffer(
            "pos_weight",
            torch.ones(N_RULES) if pos_weight is None else torch.tensor(pos_weight, dtype=torch.float32))
        # 2026-07-23 : chauffe d'un decodeur lettres FRAIS (ConvLettersDecoder)
        # -- contrairement au cas habituel (stage a = decodeur lettres deja
        # mature, gele, sa loss n'a meme pas besoin d'etre calculee), ici
        # c'est justement LUI qu'on entraine ; il faut donc calculer sa vraie
        # loss meme en stage a.
        self.train_letters_in_stage_a = train_letters_in_stage_a

        d = self.m.encoder._feat_out
        if head_hidden > 0:
            # Tete profonde (cf. ConvTajwidHead) -- experience 2026-07-23.
            self.tajwid_head = ConvTajwidHead(d, head_hidden, N_RULES)
        else:
            # Tete 2 : projection lineaire directe encodeur -> N_RULES
            # classes INDEPENDANTES (2026-07-24 : plus de blank/softmax
            # partage -- cf. load_frame_spans_lookup, chaque classe a son
            # propre sigmoide, le chevauchement de regles devient possible).
            # Volontairement minimale : classification par frame, pas de
            # modelisation de langue.
            self.tajwid_head = nn.Linear(d, N_RULES)
        self._val_letters, self._val_tajwid, self._val_n = 0.0, 0.0, 0

    def _zero_loss(self):
        """Zero RATTACHE au graphe. En stage a l'encodeur est gele : `enc` n'a
        aucun grad_fn, donc `enc.sum()*0` produit un scalaire detache et
        `backward()` echoue ("element 0 of tensors does not require grad").
        Passer par un parametre toujours entrainable garantit un graphe
        valide, y compris sur un batch sans aucun clip annote. `next(...
        parameters())` plutot que `.weight` : marche pour nn.Linear ET
        ConvTajwidHead (pas de `.weight` direct sur un nn.Module composite)."""
        return next(self.tajwid_head.parameters()).sum() * 0.0

    def _encode(self, audio, audio_len, training):
        feats, feats_len = self.m.preprocessor(
            input_signal=audio, length=audio_len)
        if training and getattr(self.m, "spec_augmentation", None) is not None:
            feats = self.m.spec_augmentation(input_spec=feats,
                                             length=feats_len)
        return self.m.encoder(audio_signal=feats, length=feats_len)

    def _tajwid_loss(self, enc, enc_len, sample_ids):
        """BCE multi-label INDEPENDANTE par classe, par frame (2026-07-24,
        remplace le CTC+softmax -- cf. load_frame_spans_lookup pour le
        POURQUOI : deux regles vraiment simultanees, ex. laam_shamsiyah et
        ghunnah sur les MEMES frames dans "ٱلنَّاسِ", ne peuvent PAS coexister
        sous un softmax partage -- l'une gagne systematiquement, l'autre
        ressort "non detectee" par construction, quelle que soit la
        prononciation. Un sigmoide par classe supprime cette concurrence :
        chaque regle est jugee independamment des autres sur les memes
        frames. UNIQUEMENT sur les echantillons annotes du batch (comme
        avant), ET seulement sur les frames reellement dans le clip (masque
        de longueur -- le batch est pad a la plus longue sequence)."""
        items = []
        for i, sid in enumerate(sample_ids.tolist()):
            entry = self.tajwid_by_index.get(sid)
            if entry:
                items.append((i, entry))
        if not items:
            return self._zero_loss(), 0

        keep = [i for i, _ in items]
        keep_t = torch.tensor(keep, device=enc.device)
        h = enc.index_select(0, keep_t).transpose(1, 2)     # (B', T, D)
        logits = self.tajwid_head(h)                        # (B', T, N_RULES)
        kept_enc_len = enc_len.index_select(0, keep_t)

        b_, t_, c_ = logits.shape
        target = torch.zeros(b_, t_, c_, device=enc.device)
        valid = torch.zeros(b_, t_, device=enc.device)
        for row, (_, (n_frames, spans)) in enumerate(items):
            length = min(int(kept_enc_len[row].item()), t_, n_frames)
            if length <= 0:
                continue
            valid[row, :length] = 1.0
            for cid, s0, e0 in spans:
                s = max(0, min(int(s0), length - 1))
                e = max(s, min(int(e0), length - 1))
                target[row, s:e + 1, cid] = 1.0

        n_valid = valid.sum().clamp(min=1.0)
        per_elem = F.binary_cross_entropy_with_logits(
            logits, target, pos_weight=self.pos_weight, reduction="none")  # (B',T,C)
        loss = (per_elem * valid.unsqueeze(-1)).sum() / (n_valid * c_)
        return loss, len(keep)

    def training_step(self, batch, batch_idx):
        audio, audio_len, tokens, tokens_len, sample_ids = batch
        enc, enc_len = self._encode(audio, audio_len, training=True)

        # ── Tete 1 : lettres + harakat (decodeur NeMo existant) ──
        if self.stage == "a" and not self.train_letters_in_stage_a:
            # Gelee : aucun gradient, on ne calcule meme pas sa loss.
            l_letters = self._zero_loss()
        else:
            logp_l = self.m.ctc_decoder(encoder_output=enc)
            l_letters = self.m.ctc_loss(
                log_probs=logp_l, targets=tokens,
                input_lengths=enc_len, target_lengths=tokens_len)

        l_tajwid, n_annot = self._tajwid_loss(enc, enc_len, sample_ids)
        loss = self.w_letters * l_letters + self.w_tajwid * l_tajwid

        self.log("train_loss", loss, prog_bar=True)
        self.log("train_tajwid", l_tajwid, prog_bar=True)
        if self.stage != "a" or self.train_letters_in_stage_a:
            self.log("train_letters", l_letters, prog_bar=True)
        self.log("annot_par_batch", float(n_annot))
        return loss

    def validation_step(self, batch, batch_idx):
        audio, audio_len, tokens, tokens_len, sample_ids = batch
        enc, enc_len = self._encode(audio, audio_len, training=False)
        logp_l = self.m.ctc_decoder(encoder_output=enc)
        l_letters = self.m.ctc_loss(
            log_probs=logp_l, targets=tokens,
            input_lengths=enc_len, target_lengths=tokens_len)
        l_tajwid, _ = self._tajwid_loss(enc, enc_len, sample_ids)
        self._val_letters += float(l_letters)
        self._val_tajwid += float(l_tajwid)
        self._val_n += 1

    def on_validation_epoch_end(self):
        n = max(self._val_n, 1)
        self.log("val_letters", self._val_letters / n, prog_bar=True)
        self.log("val_tajwid", self._val_tajwid / n, prog_bar=True)
        self._val_letters = self._val_tajwid = 0.0
        self._val_n = 0

    def configure_optimizers(self):
        params = [p for p in self.parameters() if p.requires_grad]
        opt = torch.optim.AdamW(params, lr=self.lr, weight_decay=1e-3)
        return opt


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--stage", required=True, choices=["a", "b"])
    p.add_argument("--init_nemo", required=True)
    p.add_argument("--init_tajwid_head", default=None,
                   help="state_dict de la tete 2 issu du stage a (pour b)")
    p.add_argument("--train_manifest",
                   default=str(MANIFEST_DIR / "train_manifest.jsonl"))
    p.add_argument("--val_manifest",
                   default=str(MANIFEST_DIR / "val_manifest.jsonl"))
    p.add_argument("--train_frame_spans",
                   default=str(MANIFEST_DIR / "tajwid_frame_spans_train.jsonl"),
                   help="2026-07-24 : labels PAR FRAME multi-label (cf. "
                        "build_frame_level_tajwid_labels.py), remplace le "
                        "champ text_tajwid du manifest pour la tete tajwid.")
    p.add_argument("--val_frame_spans",
                   default=str(MANIFEST_DIR / "tajwid_frame_spans_val.jsonl"))
    p.add_argument("--tajwid_pos_weight_json", default=None,
                   help="2026-07-24 : json {classe: poids} pour atténuer/"
                        "renforcer des classes dans la BCE (idee utilisateur : "
                        "les classes tres frequentes -- ham_wasl, madda_normal "
                        "-- ne doivent pas dominer l'apprentissage des classes "
                        "rares). Defaut : tout a 1.0. Cf. "
                        "calibrate_tajwid_pos_weight.py pour le calcul.")
    p.add_argument("--epochs", type=int, default=None)
    p.add_argument("--lr", type=float, default=None)
    p.add_argument("--batch_size", type=int, default=8)
    p.add_argument("--num_workers", type=int, default=0)
    p.add_argument("--max_duration", type=float, default=20.0)
    p.add_argument("--accumulate_grad_batches", type=int, default=4)
    p.add_argument("--w_letters", type=float, default=1.0)
    p.add_argument("--w_tajwid", type=float, default=1.0)
    p.add_argument("--head_hidden", type=int, default=0,
                   help="2026-07-23 : 0 = tete lineaire (defaut, historique). "
                        ">0 = ConvTajwidHead (conv1d temporel + MLP), taille "
                        "cachee donnee ici -- tete FRAICHE (incompatible avec "
                        "--init_tajwid_head, formes differentes).")
    p.add_argument("--letters_head_hidden", type=int, default=0,
                   help="2026-07-23 : 0 = decodeur CTC lettres natif NeMo "
                        "(defaut). >0 = ConvLettersDecoder (remplace "
                        "model.ctc_decoder, tete FRAICHE) -- EXPERIMENTAL, "
                        "cf. avertissement BENCHMARK_RESULTS.md sur le WER "
                        "interne trompeur pour cette tete precisement.")
    p.add_argument("--init_letters_decoder", default=None,
                   help="reprendre les poids d'un ConvLettersDecoder deja "
                        "sauvegarde (meme --letters_head_hidden)")
    p.add_argument("--limit_train_batches", type=float, default=1.0)
    p.add_argument("--out_root", default=None,
                   help="2026-07-31 : racine des checkpoints. Le SSD etait a "
                        "98 pourcent (21 Go libres) alors qu'un run de 12 "
                        "epochs pese 16,5 Go -- on ecrit sur le HDD (5,8 To). "
                        "Conforme a la regle du projet : on DEPLACE un run vers "
                        "le HDD, on ne le supprime jamais.")
    p.add_argument("--save_top_k", type=int, default=3,
                   help="2026-07-31 : -1 = GARDER TOUTES les epochs. Le defaut "
                        "3 SUPPRIME les autres checkpoints, ce qui contredit la "
                        "regle du projet (« aucune piste n'est eliminee tant que "
                        "le retour en arriere est possible ») et la demande "
                        "utilisateur du 2026-07-31. Un checkpoint fait 1,38 Go : "
                        "12 epochs = 16,5 Go, negligeable devant l'interet de "
                        "pouvoir revenir a n'importe quelle epoch.")
    p.add_argument("--run_tag", default=None)
    p.add_argument("--monitor_metric", default=None,
                   help="metrique de checkpointing (defaut : val_tajwid en "
                        "stage a, val_letters en stage b) -- 2026-07-23, "
                        "objectif val_tajwid<0.1 : permet de monitorer "
                        "val_tajwid meme en stage b sans perdre la meilleure "
                        "epoque tajwid si elle ne coincide pas avec la "
                        "meilleure epoque lettres.")
    return p.parse_args()


def main():
    args = parse_args()
    # Stage a : LR eleve (seule une tete fraiche apprend, rien a proteger).
    # Stage b : LR bas (on affine un encodeur mature sans le detruire).
    lr = args.lr if args.lr is not None else (3e-4 if args.stage == "a" else 5e-5)
    epochs = args.epochs if args.epochs is not None else (2 if args.stage == "a" else 10)

    tag = f"-{args.run_tag}" if args.run_tag else ""
    racine = Path(args.out_root) if args.out_root else OUT_ROOT
    ckpt_dir = racine / f"stage{args.stage}{tag}"
    ckpt_dir.mkdir(parents=True, exist_ok=True)

    print(f"=== Entrainement 2 tetes CTC — stage {args.stage} ===")
    print(f"  init      : {args.init_nemo}")
    print(f"  lr={lr}  epochs={epochs}  batch={args.batch_size}")
    print(f"  poids loss: lettres={args.w_letters}  tajwid={args.w_tajwid}")
    print(f"  sortie    : {ckpt_dir}")

    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        args.init_nemo)
    # RNNT neutralise (cf. docstring) -- on ne l'entraine pas, on ne l'utilise
    # pas, mais on le garde dans le .nemo pour rester compatible avec le
    # format de chargement existant.
    model.loss = _ZeroRNNTLoss()
    if hasattr(model, "joint") and hasattr(model.joint, "set_fuse_loss_wer"):
        model.joint.set_fuse_loss_wer(False, loss=None, metric=None)
    model.ctc_loss_weight = 1.0

    # Verification explicite : la tete 1 doit reutiliser le vocabulaire tel
    # quel. Un symbole PUA ici signifierait qu'on est parti du mauvais
    # checkpoint (rules-260h/piste3/piste4 au lieu de mixed-e14).
    n_pua = sum(1 for i in range(model.tokenizer.vocab_size)
                if any(0xE000 <= ord(c) <= 0xF8FF
                       for c in model.tokenizer.ids_to_tokens([i])[0]))
    print(f"  tokenizer tete 1 : {model.tokenizer.vocab_size} tokens, "
          f"{n_pua} avec symbole PUA (doit etre 0)")
    assert n_pua == 0, ("le checkpoint de depart a un vocabulaire CONTAMINE "
                        "par des symboles de regles -- partir de mixed-e14")

    if args.letters_head_hidden > 0:
        model.ctc_decoder = ConvLettersDecoder(
            model.encoder._feat_out, args.letters_head_hidden,
            model.tokenizer.vocab_size)
        if args.init_letters_decoder:
            model.ctc_decoder.load_state_dict(
                torch.load(args.init_letters_decoder, map_location="cpu"))
            print(f"  decodeur lettres repris de {args.init_letters_decoder}")
        else:
            print(f"  decodeur lettres FRAIS (ConvLettersDecoder, "
                  f"hidden={args.letters_head_hidden}) -- EXPERIMENTAL, "
                  f"revalider hors val_wer_ctc avant de faire confiance")

    # ── Donnees ──
    def data_cfg(path, is_train):
        return {
            "manifest_filepath": path, "sample_rate": 16000,
            "batch_size": args.batch_size, "shuffle": is_train,
            "num_workers": args.num_workers, "pin_memory": True,
            "max_duration": args.max_duration, "min_duration": 0.5,
            "trim_silence": False,
            # Indispensable : c'est par cet index qu'on retrouve la cible
            # tajwid de chaque echantillon (les champs personnalises du
            # manifest ne survivent pas dans la collection NeMo).
            "return_sample_id": True,
        }

    with open_dict(model.cfg):
        model.cfg.train_ds = OmegaConf.create(data_cfg(args.train_manifest, True))
        model.cfg.validation_ds = OmegaConf.create(data_cfg(args.val_manifest, False))
        # test_ds vaut "???" (mandatory) dans la config NVIDIA d'origine :
        # le laisser tel quel fait echouer toute serialisation de la config
        # (MissingMandatoryValue) -- y compris save_to() en fin de run.
        model.cfg.test_ds = OmegaConf.create(
            {**data_cfg(args.val_manifest, False), "shuffle": False})
    model.setup_training_data(model.cfg.train_ds)
    model.setup_validation_data(model.cfg.validation_ds)

    # Cibles tajwid indexees sur la collection FILTREE (max_duration/
    # min_duration ecartent des clips -> les index ne correspondent pas au
    # fichier manifest brut).
    def build_index(spans_path, dl):
        lut = load_frame_spans_lookup(spans_path)
        coll = dl.dataset.manifest_processor.collection
        out, hit = {}, 0
        for i, s in enumerate(coll):
            entry = lut.get(s.audio_file)
            if entry:
                out[i] = entry
                hit += 1
        print(f"    {Path(spans_path).name} : {len(coll)} clips retenus, "
              f"{hit} avec cible tajwid")
        return out

    print("  indexation des cibles tajwid (labels par frame) :")
    train_idx = build_index(args.train_frame_spans, model._train_dl)
    val_idx = build_index(args.val_frame_spans, model._validation_dl)
    assert train_idx, "aucune cible tajwid trouvee -- verifier les manifests"

    pos_weight = None
    if args.tajwid_pos_weight_json:
        w = json.load(open(args.tajwid_pos_weight_json, encoding="utf-8"))
        pos_weight = [float(w.get(name, 1.0)) for name in RULE_CLASSES]
        print(f"  pos_weight tajwid charge : {dict(zip(RULE_CLASSES, pos_weight))}")

    # ── Gel selon le stage ──
    # `.freeze()`/`.unfreeze()` sont des methodes NeMo (NeuralModule), absentes
    # sur ConvLettersDecoder/ConvTajwidHead (nn.Module nu) -- hasattr() avant
    # d'appeler, sinon AttributeError des qu'une tete custom remplace le
    # decodeur natif.
    def _freeze(mod):
        if hasattr(mod, "freeze"):
            mod.freeze()
        for p in mod.parameters():
            p.requires_grad = False

    def _unfreeze(mod):
        if hasattr(mod, "unfreeze"):
            mod.unfreeze()
        for p in mod.parameters():
            p.requires_grad = True

    fresh_letters = args.letters_head_hidden > 0 and not args.init_letters_decoder
    if args.stage == "a":
        _freeze(model.encoder)
        if fresh_letters:
            # Decodeur lettres FRAIS : c'est LUI qu'on chauffe ici (comme la
            # tete tajwid fraiche d'habitude) -- l'encodeur reste gele, mais
            # le decodeur lettres doit rester entrainable, pas gele avec lui.
            for p in model.ctc_decoder.parameters():
                p.requires_grad = True
            print("  Stage a : encodeur GELE, decodeur lettres FRAIS "
                  "entrainable (chauffe), tete tajwid entrainable")
        else:
            _freeze(model.ctc_decoder)
            print("  Stage a : encodeur + tete lettres GELES, seule la tete "
                  "tajwid apprend")
    else:
        for p in model.parameters():
            p.requires_grad = True
        _unfreeze(model.encoder)
        _unfreeze(model.ctc_decoder)
        print("  Stage b : tout degele, LR bas")

    trainer_module = DualHeadTrainer(
        model, train_idx, args.stage, lr, args.w_letters, args.w_tajwid,
        head_hidden=args.head_hidden,
        train_letters_in_stage_a=fresh_letters,
        pos_weight=pos_weight)
    if args.init_tajwid_head:
        # --head_hidden doit correspondre a l'architecture du checkpoint
        # repris (ex. reprendre une ConvTajwidHead(hidden=256) chauffee en
        # stage a avec --head_hidden 256 ici aussi) -- load_state_dict leve
        # une erreur claire de lui-meme si les formes ne correspondent pas,
        # pas besoin d'un garde-fou manuel en plus.
        sd = torch.load(args.init_tajwid_head, map_location="cpu")
        trainer_module.tajwid_head.load_state_dict(sd)
        print(f"  tete tajwid reprise de {args.init_tajwid_head}")
    elif args.head_hidden > 0:
        print(f"  tete tajwid FRAICHE (ConvTajwidHead, hidden={args.head_hidden})")
    trainer_module.tajwid_by_index = train_idx
    # La validation utilise le meme module : on bascule l'index au moment du
    # hook de validation (sinon les sample_id de validation seraient cherches
    # dans l'index d'entrainement -> cibles fausses).
    trainer_module._val_index = val_idx

    _orig_val_step = trainer_module.validation_step

    def val_step(batch, batch_idx):
        saved = trainer_module.tajwid_by_index
        trainer_module.tajwid_by_index = trainer_module._val_index
        try:
            return _orig_val_step(batch, batch_idx)
        finally:
            trainer_module.tajwid_by_index = saved

    trainer_module.validation_step = val_step

    n_train = sum(p.numel() for p in trainer_module.parameters()
                  if p.requires_grad)
    print(f"  parametres entrainables : {n_train/1e6:.1f}M")

    ckpt_cb = pl.callbacks.ModelCheckpoint(
        dirpath=str(ckpt_dir), filename="dual-{epoch:02d}-{val_tajwid:.3f}",
        monitor=args.monitor_metric or (
            "val_tajwid" if args.stage == "a" else "val_letters"),
        mode="min", save_top_k=args.save_top_k, save_last=True)

    trainer = pl.Trainer(
        max_epochs=epochs, accelerator="gpu", devices=1, precision="bf16-mixed",
        accumulate_grad_batches=args.accumulate_grad_batches,
        limit_train_batches=args.limit_train_batches,
        logger=CSVLogger(str(ckpt_dir), name="logs"),
        callbacks=[ckpt_cb, pl.callbacks.LearningRateMonitor()],
        log_every_n_steps=50, enable_progress_bar=True,
    )
    trainer.fit(trainer_module,
                train_dataloaders=model._train_dl,
                val_dataloaders=model._validation_dl)

    # Sauvegarde : le .nemo porte encodeur + tete 1 (mis a jour en place),
    # la tete 2 est un fichier separe (NeMo n'a pas de slot pour elle).
    out_nemo = ckpt_dir / f"stage{args.stage}-final.nemo"
    model.save_to(str(out_nemo))
    out_head = ckpt_dir / f"stage{args.stage}-tajwid-head.pt"
    torch.save(trainer_module.tajwid_head.state_dict(), str(out_head))
    msg = f"\nTermine.\n  modele  : {out_nemo}\n  tete 2  : {out_head}"
    if args.letters_head_hidden > 0:
        # ConvLettersDecoder est deja inclus dans out_nemo (submodule normal
        # du modele NeMo, serialise avec le reste) -- copie separee ici en
        # plus, uniquement par commodite (meme pattern que la tete tajwid,
        # pratique pour un chargement isole/eval rapide sans repasser par
        # restore_from() du .nemo entier).
        out_letters = ckpt_dir / f"stage{args.stage}-letters-decoder.pt"
        torch.save(model.ctc_decoder.state_dict(), str(out_letters))
        msg += f"\n  decodeur lettres (copie) : {out_letters}"
    print(msg)


if __name__ == "__main__":
    main()
