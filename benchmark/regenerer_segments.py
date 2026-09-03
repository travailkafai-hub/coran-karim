#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Regenere `word_segments_mp3quran_afasy.json` la ou le nouvel alignement
fait MIEUX que celui deja livre -- jamais ailleurs.

── LE GARDE-FOU EST LE COEUR DE CE SCRIPT ──────────────────────────────────

Mesure du 2026-08-27 (40 versets de la sourate 4) : le nouvel aligneur rend
16 versets strictement meilleurs et 5 moins bons -- dont 4:11, sain
(3 600 ms) rendu aberrant (4 315 ms). Remplacer en bloc echangerait donc des
gains contre des pertes.

Or le critere « pire duree de mot du verset » est OBJECTIF et se calcule des
deux cotes. On ne remplace un verset que si ce chiffre BAISSE. Consequence :
le resultat ne peut pas etre pire que l'existant, verset par verset, quelle
que soit la qualite du nouvel aligneur sur tel ou tel cas.

⚠️ Le fichier devient HYBRIDE (une part d'ancien, une part de neuf). Sans
consequence pour l'app : elle lit des bornes en millisecondes, elle n'a
jamais su d'ou elles venaient.

⚠️ Ne traite QUE les sourates dont l'audio est disponible localement. Les
autres sont laissees STRICTEMENT INTACTES -- une regeneration partielle est
legitime ici precisement parce que le garde-fou interdit toute degradation
(decision utilisateur 2026-08-27 : « implemente sans, ca va etre que mieux
que la situation actuelle »).

Usage :
    python3 benchmark/regenerer_segments.py <dossier_mp3> [--sourates 1,2,3,4,5]
    (les mp3 s'y nomment `7_<sourate>.mp3`, comme le cache de l'app)
"""
import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import wave
from datetime import datetime
from pathlib import Path

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from aligner_tolerant_repetition import (  # noqa: E402
    aligner, decoder_mots, mots_du_texte)

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

RACINE = BASE.parent
ASSET = RACINE / "app/assets/data/word_segments_mp3quran_afasy.json"


def pire_duree(segments):
    return max((b - a for a, b in segments), default=0.0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dossier_mp3")
    ap.add_argument("--sourates", default="1,2,3,4,5")
    args = ap.parse_args()

    segs = json.load(open(ASSET, encoding="utf-8"))
    versets = {v["verse_key"]: v for v in json.load(
        open(RACINE / "app/assets/data/quran_verses.json", encoding="utf-8"))}

    # Sauvegarde horodatee AVANT toute ecriture : regle projet, aucune piste
    # n'est eliminee tant que le retour en arriere est possible.
    sauvegarde = ASSET.with_suffix(
        f".json.avant-realignement-{datetime.now():%Y-%m-%d}")
    if not sauvegarde.exists():
        shutil.copy2(ASSET, sauvegarde)
        print(f"sauvegarde : {sauvegarde.name}")

    tmp = Path(tempfile.gettempdir()) / "regen_align"
    tmp.mkdir(exist_ok=True)
    dossier = Path(args.dossier_mp3)

    remplaces = gardes = echecs = 0
    gain_ms = 0.0
    for n_sourate in [int(x) for x in args.sourates.split(",")]:
        mp3 = dossier / f"7_{n_sourate}.mp3"
        fichier_timing = BASE / f".timing_{n_sourate}.json"
        if not mp3.exists() or not fichier_timing.exists():
            print(f"sourate {n_sourate} : audio ou minutage absent -> ignoree")
            continue
        timing = json.load(open(fichier_timing, encoding="utf-8"))
        print(f"\n── sourate {n_sourate} ({len(timing)} versets) ──")
        for e in timing:
            cle = f"{n_sourate}:{e['ayah']}"
            if cle not in segs or cle not in versets:
                continue
            wav = tmp / "v.wav"
            try:
                subprocess.run(
                    ["ffmpeg", "-y", "-loglevel", "error", "-i", str(mp3),
                     "-ss", f"{e['start_time'] / 1000:.3f}",
                     "-to", f"{e['end_time'] / 1000:.3f}",
                     "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le",
                     str(wav)], check=True)
                attendus = mots_du_texte(versets[cle]["text_uthmani"])
                prononces, mspf = decoder_mots(str(wav))
                with wave.open(str(wav), "rb") as w:
                    duree = w.getnframes() / w.getframerate() * 1000
                neuf = aligner(attendus, prononces, mspf, duree)
            except Exception as exc:  # noqa: BLE001
                # Un verset qui echoue garde son alignement d'origine : le
                # pire cas de ce script est « rien ne change ».
                print(f"  {cle} : echec ({exc}) -> ancien conserve")
                echecs += 1
                continue

            avant, apres = pire_duree(segs[cle]), pire_duree(neuf)
            # Meme nombre de mots des deux cotes, sinon on ne remplace pas :
            # une longueur differente decalerait tous les index cote app.
            if len(neuf) != len(segs[cle]):
                gardes += 1
                continue
            if apres < avant:
                segs[cle] = [[round(a, 1), round(b, 1)] for a, b in neuf]
                remplaces += 1
                gain_ms += avant - apres
                if avant > 4000:
                    print(f"  {cle:<8} {avant:>7.0f} -> {apres:>7.0f} ms")
            else:
                gardes += 1

    json.dump(segs, open(ASSET, "w", encoding="utf-8"),
              ensure_ascii=False, separators=(",", ":"))
    print(f"\nremplaces={remplaces}  gardes={gardes}  echecs={echecs}")
    print(f"audio mal attribue recupere : {gain_ms / 1000:.1f} s")
    print(f"ecrit : {ASSET}")


if __name__ == "__main__":
    main()
