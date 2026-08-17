#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Genere le minutage mot-a-mot pour TOUT le Coran, sur l'audio MP3Quran
d'Al-Afasy -- SANS AUCUNE DEPENDANCE A QURAN FOUNDATION.

POURQUOI CE SCRIPT EST DISTINCT DE mesure_aligneur_segments_mp3quran.py
-------------------------------------------------------------------------
Ce dernier MESURE l'aligneur contre `.timings_cache` (donnees Quran
Foundation) -- utile pour valider l'approche (cf.
AUDIT_EQUIVALENCES_ECRITURE_2026-08-15.md §3bis), mais sa fonction
`mesurer_verset()` a DEUX dependances a `.timings_cache` :
  1. un filtre qualite (verset exclu si un mot de la reference QF depasse
     4000ms -- signe d'un trou d'enregistrement) ;
  2. les statistiques d'erreur retournees (comparaison aux temps QF).

Aucune des deux n'a sa place dans un artefact dont le but est PRECISEMENT de
remplacer QF. Ce script reprend l'alignement lui-meme (spans_mots,
frontieres_gardees, fin_reelle_parole -- import direct, aucune reecriture)
mais retire toute lecture de `.timings_cache`. Seule source externe : le
texte du Coran local de l'app (`quran_verses.json`, deja sur Tanzil/KFGQPC,
jamais QF -- cf. PLAN_SORTIE.md).

LIMITE ASSUMEE ET DOCUMENTEE (pas cachee) : le filtre "mot suspect >4000ms"
supprimait les versets ayant un vrai trou d'enregistrement (souffle/pause/
montage propre a CET audio, cf. §2.3 de l'audit). Sans lui, une petite
fraction des versets peut porter un decalage local -- meme defaut deja connu
et mesure (~qqs % du corpus dans l'audit original), pas un defaut nouveau
introduit ici.

Usage :
    python generer_predictions_mp3quran.py --sourates 55,2,67
    python generer_predictions_mp3quran.py --toutes --reprendre
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
import onnxruntime as ort
import sentencepiece as spm

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from assainir_corpus_fautes import lire_wav  # noqa: E402
from banc_regles_gop import spans_mots  # noqa: E402
from gop_fenetre_etroite_vs_large import logprobs  # noqa: E402
# Reutilise EXACTEMENT la meme logique de frontieres que le script de mesure
# deja valide -- aucune reecriture, un seul import.
from mesure_aligneur_segments_mp3quran import (  # noqa: E402
    FRAME_MS,
    FLOOR_MS,
    RECITER_DIR,
    VERSES_JSON,
    charger_textes,
    fin_reelle_parole,
    frontieres_gardees,
)


def aligner_verset(sess, sp, mots, surah, verset):
    wav = RECITER_DIR / f"{surah}_{verset}.wav"
    if not wav.exists():
        return None
    pcm = lire_wav(wav)
    total_ms = len(pcm) / 16000.0 * 1000.0
    lp = logprobs(sess, pcm)

    spans = spans_mots(sp, lp, mots)
    if spans is None:
        return None

    onsets_ms = [None if s is None else s[0] * FRAME_MS for s in spans]
    lettres = [len(m) for m in mots]
    fin_ms = fin_reelle_parole(pcm, total_ms)
    b = frontieres_gardees(onsets_ms, lettres, fin_ms)
    return [[round(b[i], 1), round(b[i + 1], 1)] for i in range(len(mots))]


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--sourates", help="ex: 55,2,67")
    g.add_argument("--toutes", action="store_true")
    ap.add_argument("--rid", type=int, default=7)
    ap.add_argument("--modele", default=str(BASE / "models_deployes" / "fastconformer-ctc-mixed-e02"))
    ap.add_argument("--tokenizer", default=str(BASE / "tokenizers" / "tajweed_bpe_v1" / "tokenizer.model"))
    ap.add_argument("--sortie-json", default=str(BASE / "predictions_mp3quran_complet.json"))
    ap.add_argument("--reprendre", action="store_true")
    args = ap.parse_args()

    sp = spm.SentencePieceProcessor(model_file=args.tokenizer)
    sess = ort.InferenceSession(str(Path(args.modele) / "model.onnx"),
                                 providers=["CPUExecutionProvider"])
    textes = charger_textes()

    if args.toutes:
        # Toutes les sourates presentes dans le corpus MP3Quran prepare --
        # pas depuis .timings_cache (QF), depuis les WAV reellement decoupes.
        sourates = sorted({int(f.stem.split("_")[0])
                            for f in RECITER_DIR.glob("*_*.wav")})
    else:
        sourates = [int(x) for x in args.sourates.split(",")]

    predictions = {}
    deja_faites = set()
    if args.reprendre and Path(args.sortie_json).exists():
        predictions = json.load(open(args.sortie_json, encoding="utf-8"))
        deja_faites = {int(k.split(":")[0]) for k in predictions}
        print(f"reprise : {len(deja_faites)} sourates deja faites, sautees")

    total_mots = 0
    for surah in sourates:
        if surah in deja_faites:
            continue
        versets = sorted({int(k.split(":")[1]) for k in textes if k.startswith(f"{surah}:")})
        n_ok = n_echec = 0
        for v in versets:
            mots = textes.get(f"{surah}:{v}")
            if not mots:
                continue
            r = aligner_verset(sess, sp, mots, surah, v)
            if r is None:
                n_echec += 1
                continue
            predictions[f"{surah}:{v}"] = r
            total_mots += len(r)
            n_ok += 1
        print(f"sourate {surah:>3} : {n_ok} versets alignes, {n_echec} echoues "
              f"(audio absent ou alignement impossible)")
        # Sauvegarde apres CHAQUE sourate : une interruption ne perd que la
        # sourate en cours, meme discipline que le script de mesure.
        json.dump(predictions, open(args.sortie_json, "w", encoding="utf-8"),
                   ensure_ascii=False, indent=0)

    print(f"\n{len(predictions)} versets, {total_mots} mots -> {args.sortie_json}")


if __name__ == "__main__":
    main()
