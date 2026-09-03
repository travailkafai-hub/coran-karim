#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Rejoue un WAV brut a travers le modele FP32 `trois-tetes-2026-08-04-combine`
(app/android/model_pack/modeles_hors_apk/), pour comparer sa lecture a celle du
modele INT8 reellement deploye (deux-geles-int8-2026-08-22) sur le MEME audio.

Cree le 2026-08-23 a la demande explicite de l'utilisateur : PAS pour deployer
ce modele, uniquement pour le faire tourner en diagnostic sur l'audio brut
d'une session deja capturee (`stream_*.wav`).

    python3 benchmark/rejouer_wav_trois_tetes.py <stream_*.wav> [t0] [t1] [--largeurs 4,6]

Sans t0/t1 : balaie tout le fichier. Par defaut deux largeurs de fenetre (4s et
6s, meme discipline que balayer_flux_brut.py) -- UNE SEULE largeur fait
conclure "absent" sur un mot present qui n'entre pas bien dans la fenetre
(mesure du 2026-07-28, deja documentee dans le skill d'analyse de session).

── PREREQUIS DE CE MODELE (verifies le 2026-08-23, cf. le README absent --
   tout vient de l'inspection directe du .onnx et des fichiers a cote) ────────

  ONNX  entrees  audio_signal [B,80,T] float32, length [B] int64
        sorties  logprobs [B,T,1025] (Hafs, 1024 tokens + blank)
                 tajwid_logprobs [B,T,19] (19 classes, cf. rules.json)
                 encoder_state [B,T,512]
  vocab.json   liste de 1024 sous-mots SentencePiece (PAS char-level, PAS le
               format `|`=espace de balayer_flux_brut.py) -- le marqueur de
               debut de mot est `▁` (U+2581), a remplacer par un espace APRES
               le decodage CTC glouton, jamais avant.
  seuils_tajwid.json   19 seuils REELEMENT mesures ("cale sur audio reel"),
               contrairement au modele deploye ou ce fichier est un defaut vide.

Mel : reprend telle quelle `mel_numpy_reference.compute_mel_features` (deja
validee bit-pres contre NeMo, cf. son en-tete) -- ne pas la reimplementer.
"""
import argparse
import json
import os
import sys
import wave

import numpy as np
import onnxruntime as ort

# Console Windows par defaut en cp1252 : sans ceci, le premier caractere arabe
# imprime fait planter le script (UnicodeEncodeError), pas seulement l'affichage.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mel_numpy_reference import compute_mel_features

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_DIR = os.path.join(
    RACINE, "app", "android", "model_pack", "modeles_hors_apk",
    "trois-tetes-2026-08-04-combine",
)
SR = 16000
WORD_MARK = "▁"  # '▁' SentencePiece


def charger_modele():
    chemin_model = os.path.join(MODEL_DIR, "model.onnx")
    if not os.path.exists(chemin_model):
        raise SystemExit(f"modele introuvable : {chemin_model}")
    session = ort.InferenceSession(chemin_model, providers=["CPUExecutionProvider"])
    vocab = json.load(open(os.path.join(MODEL_DIR, "vocab.json"), encoding="utf-8"))
    regles = json.load(open(os.path.join(MODEL_DIR, "rules.json"), encoding="utf-8"))
    seuils = json.load(open(os.path.join(MODEL_DIR, "seuils_tajwid.json"), encoding="utf-8"))["seuils"]
    return session, vocab, regles, seuils


def decoder_ctc_glouton(logprobs_frame, vocab):
    """logprobs_frame: (T, 1025). blank = dernier index (len(vocab))."""
    blank = len(vocab)
    ids = logprobs_frame.argmax(axis=-1)
    sortie = []
    precedent = -1
    for i in ids:
        if i != precedent and i != blank:
            sortie.append(vocab[i])
        precedent = i
    texte = "".join(sortie)
    return texte.replace(WORD_MARK, " ").strip()


def tajwid_classes_actives(tajwid_logprobs_frame, regles, seuils):
    """Pour un segment (T,19) : classes dont AU MOINS UNE frame depasse son
    seuil mesure, avec la probabilite MAX observee (exp(logprob), convention
    log-sigmoid par classe -- cf. la methode deja etablie dans le skill
    d'analyse de session, Etape 4 ter)."""
    probs = np.exp(tajwid_logprobs_frame)  # (T, 19)
    actives = []
    for j, nom in enumerate(regles):
        seuil = seuils.get(nom, 0.5)
        pmax = float(probs[:, j].max()) if probs.shape[0] else 0.0
        if pmax >= seuil:
            actives.append((nom, pmax, seuil))
    actives.sort(key=lambda t: -t[1])
    return actives


def decoder_segment(session, vocab, regles, seuils, audio_segment, avec_tajwid=False):
    if len(audio_segment) < SR // 2:
        return "", []
    mel = compute_mel_features(audio_segment).astype(np.float32)[None]  # (1,80,T)
    longueur = np.array([mel.shape[2]], dtype=np.int64)
    sorties = session.run(None, {"audio_signal": mel, "length": longueur})
    logprobs, tajwid_logprobs = sorties[0][0], sorties[1][0]
    texte = decoder_ctc_glouton(logprobs, vocab)
    classes = tajwid_classes_actives(tajwid_logprobs, regles, seuils) if avec_tajwid else []
    return texte, classes


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("wav", help="stream_*.wav (flux brut d'une session, PCM 16 kHz mono 16 bits)")
    ap.add_argument("t0", nargs="?", type=float, default=0.0)
    ap.add_argument("t1", nargs="?", type=float, default=None)
    ap.add_argument("--largeurs", default="4,6", help="largeurs de fenetre en secondes, separees par une virgule")
    ap.add_argument("--tajwid", action="store_true", help="affiche aussi les classes tajwid actives par fenetre")
    args = ap.parse_args()

    with wave.open(args.wav, "rb") as w:
        assert w.getframerate() == SR, f"attendu {SR} Hz, recu {w.getframerate()}"
        audio = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
    duree_totale = len(audio) / SR
    t1 = args.t1 if args.t1 is not None else duree_totale
    largeurs = [float(x) for x in args.largeurs.split(",")]

    print(f"modele : {MODEL_DIR}")
    print(f"wav    : {args.wav} ({duree_totale:.1f}s)")
    print(f"plage  : [{args.t0:.1f}, {t1:.1f}]s, largeurs {largeurs}")
    print()

    session, vocab, regles, seuils = charger_modele()

    for L in largeurs:
        print(f"--- largeur {L:g}s ---")
        t = args.t0
        pas = L / 2
        while t + L <= t1:
            segment = audio[int(t * SR):int((t + L) * SR)]
            texte, classes = decoder_segment(session, vocab, regles, seuils, segment, avec_tajwid=args.tajwid)
            if texte:
                ligne = f"  [{t:7.1f}-{t + L:7.1f}] {texte}"
                if args.tajwid and classes:
                    ligne += "   tajwid: " + ", ".join(f"{n}={p:.2f}(>{s:.2f})" for n, p, s in classes[:4])
                print(ligne)
            t += pas
        print()


if __name__ == "__main__":
    main()
