#!/usr/bin/env python3
"""Corpus de l'ETAPE 1 : encodeur + tete lettres, avec des fautes EN PHRASE.

CE QUI CHANGE PAR RAPPORT AU CORPUS ACTUEL, et pourquoi.

Le manifeste `nemo_manifests_dual/train_manifest.jsonl` contient 81 380 entrees
a fautes deliberees -- mais seulement 16 276 clips DISTINCTS, repetes ~5 fois
pour peser face au Coran recite, et **tous des mots ISOLES** (duree mediane
1,71 s, 1 mot, maximum 1). Le modele n'a donc jamais vu une PHRASE contenant
une faute : il a appris deux regimes disjoints -- court = fidele, long =
canonique (`piege_contre_exemples_mots_isoles`). C'est la cause racine du fait
qu'une vraie faute passe au VERT dans l'app.

Ce script fait deux choses, et rien d'autre :

  1. RETIRE les clips dont l'audio dit le mot CORRECT alors que l'etiquette dit
     le contraire. Mesure du 2026-07-31 sur les 18 195 clips : 1 117 sont dans
     ce cas (6,1 %). Le QA d'origine ne pouvait pas les voir -- il acceptait
     jusqu'a CER 0,5 contre le texte demande, ce qui laisse passer une
     reecriture canonique a une lettre pres.
  2. AJOUTE les phrases a faute assemblee, dont l'audibilite est verifiee mot
     par mot (`assembler_phrases_fautees.py`).

CE QU'IL NE FAIT PAS. Il ne touche ni au Coran recite, ni a
`arabic_speech_corpus`, ni aux entrees annotees tajwid : l'etape 1 ne concerne
que la tete lettres, et changer plusieurs choses a la fois rendrait le resultat
ininterpretable.

Usage :
    python3 build_manifest_phrases_fautees.py --repetitions 5
"""
import argparse
import json
import os
import wave
from collections import Counter
from pathlib import Path

BASE = Path(__file__).parent
DUAL = BASE / "nemo_manifests_dual"


def duree(chemin):
    try:
        with wave.open(str(chemin)) as w:
            return w.getnframes() / w.getframerate()
    except Exception:
        return None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--source", default=str(DUAL / "train_manifest.jsonl"))
    p.add_argument("--inaudibles",
                   default=str(BASE / "data/tts_augmentation/manifest_inaudible.jsonl"))
    p.add_argument("--phrases", default=str(BASE / "data/tts_phrases_concat"))
    p.add_argument("--repetitions", type=int, default=5,
                   help="repetitions des phrases fautees, comme les mots isoles")
    p.add_argument("--sortie", default=str(DUAL / "train_manifest_phrases.jsonl"))
    args = p.parse_args()

    ecartes = set()
    if Path(args.inaudibles).exists():
        for l in open(args.inaudibles, encoding="utf-8"):
            ecartes.add(json.loads(l)["clip"])
    print(f"{len(ecartes)} clips ecartes (audio = mot correct, etiquette = faute)")

    garde, retire = [], 0
    familles = Counter()
    for l in open(args.source, encoding="utf-8"):
        d = json.loads(l)
        p_ = d["audio_filepath"]
        if "tts_augmentation" in p_ and os.path.basename(p_) in ecartes:
            retire += 1
            continue
        familles["faute mot isole" if "tts_augmentation" in p_
                 else "MSA (arabic_speech_corpus)" if "arabic_speech_corpus" in p_
                 else "Coran recite"] += 1
        garde.append(d)
    print(f"{retire} entrees retirees du manifeste source ({len(garde)} restantes)")

    phrases = Path(args.phrases)
    ajoutees = 0
    if (phrases / "manifest.jsonl").exists():
        for l in open(phrases / "manifest.jsonl", encoding="utf-8"):
            r = json.loads(l)
            for clip, texte in ((r["clip_faute"], r["text"]),
                                (r["clip_correct"], r["correct_text"])):
                chemin = phrases / "wav" / clip
                d_ = duree(chemin)
                if d_ is None:
                    continue
                # La version CORRECTE est ajoutee elle aussi, et par le meme
                # chemin d'assemblage : sans elle le modele apprendrait « ca
                # sonne colle-a-colle donc il y a une faute », c'est-a-dire un
                # detecteur de montage et non un detecteur de faute.
                for _ in range(args.repetitions):
                    garde.append({"audio_filepath": str(chemin), "duration": round(d_, 3),
                                  "text": texte, "text_tajwid": None})
                    ajoutees += 1
    print(f"{ajoutees} entrees de phrases a faute ajoutees "
          f"({args.repetitions} repetitions)")

    with open(args.sortie, "w", encoding="utf-8") as g:
        for d in garde:
            g.write(json.dumps(d, ensure_ascii=False) + "\n")
    familles["faute EN PHRASE (nouveau)"] = ajoutees
    print(f"\n{len(garde)} entrees -> {args.sortie}")
    for k, v in familles.most_common():
        print(f"  {k:32} {v:7d}  {100*v/len(garde):5.1f} %")


if __name__ == "__main__":
    main()
