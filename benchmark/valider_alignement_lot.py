#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Valide `aligner_tolerant_repetition` sur un LOT de versets d'une sourate.

Prealable a toute regeneration du jeu de donnees : le prototype n'avait ete
mesure que sur 4:3. Un correctif valide sur un seul cas ne dit rien de ce
qu'il fait aux 6 235 autres -- et c'est precisement la sorte de conclusion
que ce projet interdit de tirer.

Ce que le lot verifie, verset par verset :
  - la pire duree de mot BAISSE (le defaut vise) ;
  - aucun verset SAIN ne se met a porter une duree aberrante (non-regression,
    la question qui compte vraiment) ;
  - la couverture des mots ancres reste elevee (un alignement qui
    n'ancrerait plus rien « corrigerait » les durees en n'alignant plus).

Usage :
    python3 benchmark/valider_alignement_lot.py <sourate.mp3> <n_sourate> \
        [--versets 3,7,43] [--max N]
"""
import argparse
import json
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from aligner_tolerant_repetition import (  # noqa: E402
    aligner, apparier, decoder_mots, mots_du_texte)

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

RACINE = BASE.parent
#: Au-dela, une duree de mot est tenue pour aberrante (cf. la mesure du
#: 2026-08-27 : hors anomalies, les mots d'Al-Afasy tiennent sous ~2,5 s).
SEUIL_ABERRANT_MS = 4000.0


def extraire(mp3: Path, debut_ms: int, fin_ms: int, sortie: Path):
    """Decoupe le verset en WAV 16 kHz mono -- le format qu'attend le modele."""
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(mp3),
         "-ss", f"{debut_ms / 1000:.3f}", "-to", f"{fin_ms / 1000:.3f}",
         "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", str(sortie)],
        check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mp3")
    ap.add_argument("sourate", type=int)
    ap.add_argument("--versets", default=None,
                    help="liste d'ayat, sinon un echantillon automatique")
    ap.add_argument("--max", type=int, default=12)
    args = ap.parse_args()

    segs = json.load(open(
        RACINE / "app/assets/data/word_segments_mp3quran_afasy.json",
        encoding="utf-8"))
    versets = {v["verse_key"]: v for v in json.load(
        open(RACINE / "app/assets/data/quran_verses.json", encoding="utf-8"))}
    timing = {e["ayah"]: e for e in json.load(
        open(BASE / f".timing_{args.sourate}.json", encoding="utf-8"))}

    if args.versets:
        ayat = [int(x) for x in args.versets.split(",")]
    else:
        # Echantillon MIXTE : les pires anomalies ET des versets sains. Ne
        # mesurer que les cas malades dirait seulement « ca corrige », jamais
        # « ca ne casse rien ».
        s = {k: v for k, v in segs.items() if k.startswith(f"{args.sourate}:")}
        malades = sorted(
            ((max(b - a for a, b in v), k) for k, v in s.items()
             if any(b - a > SEUIL_ABERRANT_MS for a, b in v)), reverse=True)
        sains = [k for k, v in s.items()
                 if not any(b - a > SEUIL_ABERRANT_MS for a, b in v)]
        moitie = max(1, args.max // 2)
        ayat = ([int(k.split(":")[1]) for _, k in malades[:moitie]] +
                [int(k.split(":")[1]) for k in sains[:args.max - moitie]])

    mp3 = Path(args.mp3)
    tmp = Path(tempfile.gettempdir()) / "valider_align"
    tmp.mkdir(exist_ok=True)

    print(f"{'verset':<8} {'mots':>5} {'dits':>5} {'pire AVANT':>11} "
          f"{'pire APRES':>11} {'ancres':>7}  verdict")
    ameliores = casses = inchanges = garde_mieux = 0
    gain_total = []
    for ayah in ayat:
        cle = f"{args.sourate}:{ayah}"
        if cle not in segs or ayah not in timing:
            continue
        t = timing[ayah]
        wav = tmp / f"{args.sourate}_{ayah}.wav"
        extraire(mp3, t["start_time"], t["end_time"], wav)
        attendus = mots_du_texte(versets[cle]["text_uthmani"])
        prononces, mspf = decoder_mots(str(wav))
        with wave.open(str(wav), "rb") as w:
            duree = w.getnframes() / w.getframerate() * 1000
        neuf = aligner(attendus, prononces, mspf, duree)
        paires = apparier(attendus, prononces)

        avant = max(b - a for a, b in segs[cle])
        apres = max(b - a for a, b in neuf)
        couverture = 100 * len(paires) / max(1, len(attendus))

        # ── LE GARDE-FOU : ON NE REMPLACE QUE CE QUI S'AMELIORE ───────────
        #
        # MESURE QUI L'IMPOSE (lot de 40 versets, sourate 4, 2026-08-27) :
        # 16 versets strictement meilleurs, mais 5 moins bons -- dont 4:11,
        # sain (3 600 ms) rendu aberrant (4 315 ms). Regenerer en bloc
        # echangerait donc des gains contre des pertes, sans necessite : le
        # critere « pire duree de mot » est objectif et se calcule des deux
        # cotes. On garde, verset par verset, l'alignement le moins mauvais.
        #
        # Consequence assumee : le jeu de donnees devient HYBRIDE (une part
        # d'ancien, une part de neuf). C'est sans effet pour l'app, qui lit
        # des bornes en ms sans savoir d'ou elles viennent -- et c'est le
        # seul moyen d'ameliorer sans jamais degrader.
        retenu = "NEUF" if apres < avant else "ancien"
        if retenu == "NEUF":
            garde_mieux += 1

        if avant > SEUIL_ABERRANT_MS and apres <= SEUIL_ABERRANT_MS:
            verdict, marque = "CORRIGE", "+"
            ameliores += 1
        elif apres > SEUIL_ABERRANT_MS and avant <= SEUIL_ABERRANT_MS:
            verdict, marque = "REGRESSION", "!"
            casses += 1
        elif apres > SEUIL_ABERRANT_MS:
            verdict, marque = "encore aberrant", "~"
            inchanges += 1
        else:
            verdict, marque = "ok", " "
            inchanges += 1
        pire_retenu = min(avant, apres)
        gain_total.append(avant - pire_retenu)
        print(f"{cle:<8} {len(attendus):>5} {len(prononces):>5} "
              f"{avant:>10.0f}  {apres:>10.0f}  {couverture:>6.0f}% {marque} "
              f"{verdict:<16} -> {retenu}")

    print(f"\nSANS garde-fou : corriges={ameliores}  regressions={casses}  "
          f"sans changement de statut={inchanges}")
    print(f"AVEC garde-fou : {garde_mieux} verset(s) remplace(s), "
          f"0 regression par construction ; "
          f"gain cumule {sum(gain_total) / 1000:.1f} s d'audio mal attribue")


if __name__ == "__main__":
    main()
