#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Prepare un corpus PAR VERSET a partir des fichiers MP3Quran (sourate
entiere) d'Al-Afasy, pour que `mesure_aligneur_segments.py` tourne dessus
sans modification -- meme structure que `data/train_wav_local/Alafasy_128kbps`
(WAV nommes `{surah}_{verset}.wav`, `lire_wav` s'occupe du reechantillonnage).

POURQUOI CE SCRIPT EXISTE (2026-08-16)
---------------------------------------
`AUDIT_EQUIVALENCES_ECRITURE_2026-08-15.md` §2 mesure l'aligneur contre de
l'audio EVERYAYAH (`Alafasy_128kbps`), pas contre MP3Quran -- l'app utilise
maintenant MP3Quran (cf. `app/lib/services/mp3quran_api.dart`). Comparaison
faite le 2026-08-16 sur le seul verset 1:1 : 5820 ms (everyayah, predictions
existantes) contre 4700 ms (MP3Quran, `ayat_timing`) -- 24% d'ecart, TROP pour
etre du bruit. Reutiliser les predictions everyayah telles quelles serait
mesurer l'aligneur sur un audio, et l'appliquer a un AUTRE : exactement le
piege de desynchronisation deja documente au §2.3 du meme audit (verset 2:213,
trou de 6s propre a UN enregistrement precis).

La bonne methode, confirmee par l'utilisateur : refaire la mesure sur le VRAI
audio MP3Quran, pas deviner un decalage entre les deux sources.

CE QUE CE SCRIPT FAIT, ET NE FAIT PAS
---------------------------------------
Fait : telecharge (une fois, cache local), decoupe par verset via
`ayat_timing` (deja verifie exact sur device -- meme source que celle que
l'app utilise reellement), ecrit des WAV 16 kHz mono.
Ne fait PAS : aucune inference de modele, aucun alignement mot-a-mot -- ca
reste le travail de `mesure_aligneur_segments.py`, qui exige le GPU/venv
absents de ce poste (verifie : ni sentencepiece, ni onnxruntime-gpu, ni
nvidia-smi ici). Ce script, lui, ne demande que ffmpeg + requetes HTTP :
tourne entierement sur CE poste, prepare le terrain pour l'autre.

Usage :
    python preparer_corpus_mp3quran.py --sourates 55,2,67   # echantillon
    python preparer_corpus_mp3quran.py --toutes              # Coran complet
"""
import argparse
import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

BASE = Path(__file__).parent
CACHE_MP3 = BASE / ".cache_mp3quran_sourates"
SORTIE = BASE / "data" / "train_wav_local" / "Alafasy_mp3quran"

# reciter_id=123 chez MP3Quran, moshaf Hafs-Murattal, verifie le 2026-08-13
# (cf. mp3quran_api.dart) -- meme voix qu'Alafasy_128kbps (everyayah), mais
# un CONTENEUR different (sourate entiere, pas un fichier par verset).
SERVEUR_AUDIO = "https://server8.mp3quran.net/afs/"
READ_ID = 123  # identifiant MP3Quran du minutage propre a CE recitateur --
               # PAS une valeur generique par riwaya, piege deja tombe le
               # 2026-08-16 (read=1 donnait le minutage d'un AUTRE recitateur,
               # cf. mp3quran_api.dart).


def url_ayat_timing(surah: int) -> str:
    return (f"https://www.mp3quran.net/api/v3/ayat_timing"
            f"?surah={surah}&read={READ_ID}&mp3quran=1")


def telecharger_json(url: str):
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.loads(r.read().decode("utf-8"))


def chemin_mp3_sourate(surah: int) -> Path:
    CACHE_MP3.mkdir(parents=True, exist_ok=True)
    return CACHE_MP3 / f"{surah:03d}.mp3"


def telecharger_sourate(surah: int) -> Path:
    dest = chemin_mp3_sourate(surah)
    if dest.exists() and dest.stat().st_size > 0:
        return dest
    url = f"{SERVEUR_AUDIO}{surah:03d}.mp3"
    print(f"  telechargement {url} ...", flush=True)
    tmp = dest.with_suffix(".part")
    urllib.request.urlretrieve(url, tmp)
    tmp.rename(dest)
    return dest


def decouper_versets(surah: int, mp3: Path, timing: list) -> int:
    """Un `ffmpeg -ss/-to` par verset -- deterministe, pas de reencodage
    approximatif (copie du flux source puis conversion unique en WAV via -ar/-ac).
    """
    SORTIE.mkdir(parents=True, exist_ok=True)
    n = 0
    for entree in timing:
        ayah = entree["ayah"]
        debut_s = entree["start_time"] / 1000.0
        fin_s = entree["end_time"] / 1000.0
        cible = SORTIE / f"{surah}_{ayah}.wav"
        if cible.exists() and cible.stat().st_size > 0:
            n += 1
            continue
        cmd = [
            "ffmpeg", "-y", "-loglevel", "error",
            "-ss", f"{debut_s:.3f}", "-to", f"{fin_s:.3f}",
            "-i", str(mp3),
            "-ar", "16000", "-ac", "1",
            str(cible),
        ]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0 or not cible.exists():
            print(f"  ECHOUE {surah}:{ayah} -- {r.stderr.strip()[:200]}",
                  file=sys.stderr)
            continue
        n += 1
    return n


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--sourates", help="liste separee par des virgules, ex. 55,2,67")
    g.add_argument("--toutes", action="store_true", help="les 114 sourates")
    args = ap.parse_args()

    sourates = (list(range(1, 115)) if args.toutes
                else [int(s) for s in args.sourates.split(",")])

    total_versets = 0
    for surah in sourates:
        print(f"Sourate {surah} :")
        try:
            timing = telecharger_json(url_ayat_timing(surah))
        except Exception as e:
            print(f"  minutage indisponible : {e}", file=sys.stderr)
            continue
        if not timing:
            print("  minutage vide -- sourate ignoree", file=sys.stderr)
            continue
        try:
            mp3 = telecharger_sourate(surah)
        except Exception as e:
            print(f"  telechargement audio echoue : {e}", file=sys.stderr)
            continue
        n = decouper_versets(surah, mp3, timing)
        total_versets += n
        print(f"  {n}/{len(timing)} versets decoupes -> {SORTIE}")

    print(f"\nTotal : {total_versets} versets prets dans {SORTIE}")
    print("Prochaine etape (sur le poste GPU) : pointer RECITER_DIR de "
          "mesure_aligneur_segments.py vers ce dossier et relancer la mesure.")


if __name__ == "__main__":
    main()
