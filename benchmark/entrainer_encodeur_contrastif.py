#!/usr/bin/env python3
"""PISTE 10 -- entrainement CONTRASTIF de l'encodeur sur des paires (correct, faute).

Demande utilisateur explicite (2026-07-31) : « puis on a le modele actuel
aucun risque je fonce sur le 10 ». C'est le seul levier identifie au-dessus du
plafond mesure de la regle C / tete 3 (~31 % de detection a 2 % de collateral).

── LE MECANISME, ET POURQUOI LE CTC SEUL N'Y ARRIVE PAS ──────────────────
Le CTC standard entraine UNE SEULE quantite : la vraisemblance du texte
CORRECT. Il n'apprend JAMAIS la marge contre un texte faux -- deux passages
avec la meme transcription mais des prononciations differentes peuvent avoir
exactement la meme loss. C'est le "biais canonique" mesure le 2026-07-31
(gop_C median = +0,109 POSITIF sur des mots dont la faute est verifiee
audible) : le modele prefere le canonique meme quand l'audio dit autre chose.

La loss ici entraine DIRECTEMENT la grandeur que l'app lit pour juger :

    forced(cible | audio)  =  -CTC(audio, cible)      (log-vraisemblance FORCEE)

    L  =  CTC(correct , texte_correct)                         (1: transcrire, normal)
       +  CTC(fautif  , texte_FAUTIF)                          (2: transcrire la faute fidelement)
       +  lambda * relu( marge - [ forced(texte_correct | correct)
                                  - forced(texte_correct | fautif) ] )   (3: le contraste)

Les termes 1 et 2 maintiennent la transcription -- sans eux l'encodeur pourrait
« tricher » en apprenant a reconnaitre la fabrique TTS plutot que la
phonetique (audio_correct et audio_fautif sont assembles IDENTIQUEMENT, la
couture ne doit rien predire, mais le risque residuel existe). Le terme 3 est
la marge elle-meme.

── CE QUE CE SCRIPT NE FAIT PAS ──────────────────────────────────────────
Il ne merge rien dans le modele deploye. Il produit un .nemo a cote, comme
tous les runs du projet (aucune piste eliminee tant que le retour en arriere
est possible). Rien n'est pousse sur le telephone sans une recette de
non-regression sur recitation JUSTE -- ce script ne peut prouver que la
detection s'ameliore, jamais que la transcription tient.

── RISQUE CONNU, A SURVEILLER ACTIVEMENT PENDANT L'ENTRAINEMENT ──────────
L'encodeur peut apprendre a discriminer les ARTEFACTS DE SYNTHESE plutot que
la phonetique -- il gagnerait sur ce banc sans avoir rien appris d'utile, et
le banc ne le verrait pas puisqu'il est fait de la meme matiere synthetique.
Deux protections : (a) la loss CTC de transcription reste active en
permanence -- un encodeur qui ne regarderait que les artefacts perdrait sur
elle ; (b) __main__ logue AUC(train) et l'ecart aux checkpoints -- une AUC qui
grimpe alors que val_letters stagne est le signal d'alerte.
"""
import os

os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import argparse
import json
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F
import lightning.pytorch as pl
from lightning.pytorch.loggers import CSVLogger
from torch.utils.data import Dataset, DataLoader

BASE = Path(__file__).parent
DEFAULT_MANIFEST = BASE / "data" / "tts_phrases_concat" / "manifest.jsonl"
DEFAULT_WAV_DIR = BASE / "data" / "tts_phrases_concat" / "wav"
OUT_ROOT = BASE / "models" / "fastconformer-contrastif-v1"


def lire_wav16(p):
    import soundfile as sf
    x, sr = sf.read(str(p), dtype="float32")
    assert sr == 16000, f"{p} n'est pas a 16 kHz ({sr})"
    if x.ndim > 1:
        x = x.mean(axis=1)
    return x


class PairesDataset(Dataset):
    """Une entree = UNE paire (audio_correct, texte_correct, audio_fautif,
    texte_fautif). Le champ `test` marque les lignes tenues a l'ecart -- MEME
    partition que le reste du projet (cf. tete_encodeur_ecart.py), pour que les
    mesures de detection restent comparables entre les pistes."""

    def __init__(self, manifest_path, wav_dir, tokenizer, n_test, entrainement):
        # PARTITION DETERMINISTE (k < n_test), IDENTIQUE a
        # tete_encodeur_ecart.py sur ce MEME manifeste (meme ordre de fichier,
        # aucun melange). Sans cette identite, la detection mesuree ici ne
        # serait plus comparable aux 27 % (regle C) / 31 % (tete 3) deja
        # etablis -- ce seraient trois bancs differents qui se ressembleraient
        # par coincidence.
        lignes = [json.loads(l) for l in open(manifest_path, encoding="utf-8")]
        self.wav_dir = Path(wav_dir)
        self.tok = tokenizer
        self.items = [
            l for k, l in enumerate(lignes)
            if (k < n_test) != entrainement
        ]

    def __len__(self):
        return len(self.items)

    def __getitem__(self, i):
        l = self.items[i]
        correct = lire_wav16(self.wav_dir / l["clip_correct"])
        fautif = lire_wav16(self.wav_dir / l["clip_faute"])
        return {
            "correct": correct, "fautif": fautif,
            "texte_correct": self.tok.text_to_ids(l["correct_text"]),
            "texte_fautif": self.tok.text_to_ids(l["text"]),
        }


def assembler_batch(items, pad_id=0):
    """Un batch = 2N sequences (N correctes + N fautives) empilees, pour ne
    lancer l'encodeur qu'UNE fois sur le lot entier -- deux forward() separes
    doubleraient le cout sans raison, l'encodeur est le meme dans les deux cas."""
    audios = [it["correct"] for it in items] + [it["fautif"] for it in items]
    lens = torch.tensor([len(a) for a in audios], dtype=torch.int64)
    maxlen = int(lens.max())
    batch = torch.zeros(len(audios), maxlen, dtype=torch.float32)
    for i, a in enumerate(audios):
        batch[i, :len(a)] = torch.from_numpy(a)

    def pad_ids(seqs):
        m = max(len(s) for s in seqs)
        out = torch.full((len(seqs), m), pad_id, dtype=torch.int64)
        tl = torch.tensor([len(s) for s in seqs], dtype=torch.int64)
        for i, s in enumerate(seqs):
            out[i, :len(s)] = torch.tensor(s, dtype=torch.int64)
        return out, tl

    tc_ids, tc_len = pad_ids([it["texte_correct"] for it in items])
    tf_ids, tf_len = pad_ids([it["texte_fautif"] for it in items])
    n = len(items)
    return {
        "audio": batch, "audio_len": lens, "n": n,
        "texte_correct_ids": tc_ids, "texte_correct_len": tc_len,
        "texte_fautif_ids": tf_ids, "texte_fautif_len": tf_len,
    }


class ModuleContrastif(pl.LightningModule):
    """Encodeur + tete lettres du modele NeMo, EXTRAITS pour un entrainement
    autonome -- pas de wrapper dual-head ici, une seule tete, la loss est ce
    qui change."""

    def __init__(self, nemo_model, lr, marge, lam, blank_id):
        super().__init__()
        self.encoder = nemo_model.encoder
        self.ctc_decoder = nemo_model.ctc_decoder
        self.preprocessor = nemo_model.preprocessor
        self.lr = lr
        self.marge = marge
        self.lam = lam
        self.blank_id = blank_id
        self._auc_train = []

    def _forced(self, logp, logp_len, ids, ids_len):
        """-CTC(audio, texte) par exemple du batch, PAS reduit -- c'est le
        score force lui-meme (log-vraisemblance), la grandeur que l'app lit."""
        return -F.ctc_loss(
            logp.transpose(0, 1), ids, logp_len, ids_len,
            blank=self.blank_id, reduction="none", zero_infinity=True,
        )

    def _pas(self, batch):
        mel, mel_len = self.preprocessor(
            input_signal=batch["audio"], length=batch["audio_len"])
        enc, enc_len = self.encoder(audio_signal=mel, length=mel_len)
        logits = self.ctc_decoder(encoder_output=enc)
        logp = F.log_softmax(logits, dim=-1)
        n = batch["n"]
        logp_c, len_c = logp[:n], enc_len[:n]
        logp_f, len_f = logp[n:], enc_len[n:]

        # (1) transcrire normalement l'audio correct.
        l_correct = -self._forced(logp_c, len_c, batch["texte_correct_ids"],
                                  batch["texte_correct_len"]).mean()
        # (2) transcrire FIDELEMENT la faute -- pas le texte correct.
        l_fautif = -self._forced(logp_f, len_f, batch["texte_fautif_ids"],
                                 batch["texte_fautif_len"]).mean()
        # (3) le contraste : forced(texte_correct | correct) doit DEPASSER
        #     forced(texte_correct | fautif) d'au moins `marge`.
        f_sur_correct = self._forced(logp_c, len_c, batch["texte_correct_ids"],
                                     batch["texte_correct_len"])
        f_sur_fautif = self._forced(logp_f, len_f, batch["texte_correct_ids"],
                                    batch["texte_correct_len"])
        ecart = f_sur_correct - f_sur_fautif
        l_contraste = F.relu(self.marge - ecart).mean()

        auc = float((ecart > 0).float().mean())
        return l_correct + l_fautif + self.lam * l_contraste, {
            "l_correct": l_correct.item(), "l_fautif": l_fautif.item(),
            "l_contraste": l_contraste.item(), "auc_batch": auc,
        }

    def training_step(self, batch, _):
        loss, m = self._pas(batch)
        self._auc_train.append(m["auc_batch"])
        self.log_dict({f"train_{k}": v for k, v in m.items()}, prog_bar=True)
        self.log("train_loss", loss, prog_bar=True)
        return loss

    def validation_step(self, batch, _):
        loss, m = self._pas(batch)
        self.log_dict({f"val_{k}": v for k, v in m.items()}, prog_bar=True,
                      sync_dist=False)
        self.log("val_loss", loss, prog_bar=True)
        return loss

    def on_train_epoch_end(self):
        # SIGNAL D'ALERTE (cf. docstring) : une AUC(train) qui grimpe alors que
        # val_letters (la transcription) stagne suggere que l'encodeur
        # discrimine un artefact de synthese plutot que la phonetique.
        if self._auc_train:
            print(f"  [contrastif] AUC(train, epoch) = "
                  f"{sum(self._auc_train)/len(self._auc_train):.3f}")
        self._auc_train = []

    def configure_optimizers(self):
        return torch.optim.AdamW(self.parameters(), lr=self.lr)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--nemo", required=True)
    p.add_argument("--manifest", default=str(DEFAULT_MANIFEST))
    p.add_argument("--wav_dir", default=str(DEFAULT_WAV_DIR))
    p.add_argument("--marge", type=float, default=1.0,
                   help="marge cible entre forced(correct) et forced(fautif) "
                        "sur le MEME texte correct. Depart 1,0 nat -- a "
                        "calibrer, cf. banc de detection.")
    p.add_argument("--lam", type=float, default=1.0)
    p.add_argument("--lr", type=float, default=3e-5,
                   help="bas : on ne veut pas detruire l'acquis de "
                        "transcription pour une amelioration de marge")
    p.add_argument("--epochs", type=int, default=8)
    p.add_argument("--batch_size", type=int, default=4,
                   help="4 paires = 8 sequences par batch (correct+fautif)")
    p.add_argument("--n_test", type=int, default=189,
                   help="premieres N lignes tenues a l'ecart -- MEME valeur et "
                        "MEME logique (k < n_test) que tete_encodeur_ecart.py, "
                        "sur le meme manifeste, pour rester comparable aux "
                        "27 %% / 31 %% deja mesures.")
    p.add_argument("--out_root", default=None)
    p.add_argument("--run_tag", default=None)
    p.add_argument("--save_top_k", type=int, default=-1)
    p.add_argument("--limit_train_batches", type=float, default=1.0,
                   help="pour un essai rapide avant le run complet")
    a = p.parse_args()

    import nemo.collections.asr as nemo_asr
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        a.nemo, map_location="cpu")
    tok = model.tokenizer
    # MEME PATTERN que build_confusable_splice_augmentation.py et les autres
    # scripts du projet : le blank CTC est le DERNIER index, apres les tokens
    # du vocabulaire -- pas un attribut interne de NeMo dont la presence n'est
    # pas garantie d'une version a l'autre.
    blank_id = tok.vocab_size

    n = sum(1 for _ in open(a.manifest, encoding="utf-8"))
    print(f"{n} paires | {min(a.n_test, n)} tenues a l'ecart "
          f"(k < {a.n_test}, deterministe, meme partition que "
          f"tete_encodeur_ecart.py)")

    ds_train = PairesDataset(a.manifest, a.wav_dir, tok, a.n_test, True)
    ds_val = PairesDataset(a.manifest, a.wav_dir, tok, a.n_test, False)
    print(f"train={len(ds_train)}  val={len(ds_val)}")

    dl_train = DataLoader(ds_train, batch_size=a.batch_size, shuffle=True,
                          num_workers=0, collate_fn=assembler_batch)
    dl_val = DataLoader(ds_val, batch_size=a.batch_size, shuffle=False,
                        num_workers=0, collate_fn=assembler_batch)

    trainer_module = ModuleContrastif(model, a.lr, a.marge, a.lam, blank_id)
    n_param = sum(p.numel() for p in trainer_module.parameters() if p.requires_grad)
    print(f"parametres entrainables : {n_param/1e6:.1f}M (encodeur COMPLET, "
          f"contrairement au stage a de la tete tajwid)")

    racine = Path(a.out_root) if a.out_root else OUT_ROOT
    tag = f"-{a.run_tag}" if a.run_tag else ""
    ckpt_dir = racine / f"contrastif{tag}"
    ckpt_dir.mkdir(parents=True, exist_ok=True)
    print(f"sortie : {ckpt_dir}")

    ckpt_cb = pl.callbacks.ModelCheckpoint(
        dirpath=str(ckpt_dir), filename="ctr-{epoch:02d}-{val_auc_batch:.3f}",
        monitor="val_auc_batch", mode="max", save_top_k=a.save_top_k,
        save_last=True)

    trainer = pl.Trainer(
        max_epochs=a.epochs, accelerator="gpu", devices=1,
        precision="bf16-mixed", callbacks=[ckpt_cb],
        logger=CSVLogger(str(ckpt_dir), name="logs"),
        log_every_n_steps=10, enable_progress_bar=True,
        gradient_clip_val=1.0, limit_train_batches=a.limit_train_batches,
    )
    trainer.fit(trainer_module, dl_train, dl_val)

    out_nemo = ckpt_dir / "contrastif-final.nemo"
    model.encoder.load_state_dict(trainer_module.encoder.state_dict())
    model.ctc_decoder.load_state_dict(trainer_module.ctc_decoder.state_dict())
    model.save_to(str(out_nemo))
    print(f"\nmodele final ecrit : {out_nemo}")
    print("RESTE, obligatoire avant tout deploiement :")
    print("  1. banc_regles_gop.py / tete_encodeur_ecart.py sur les 189 phrases "
          "tenues a l'ecart -- la detection a-t-elle vraiment bouge ?")
    print("  2. recette device sur recitation JUSTE -- la transcription tient-elle ?")
    print("  Un gain de detection SANS le point 2 est suspect (triche possible).")


if __name__ == "__main__":
    main()
