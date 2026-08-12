#!/usr/bin/env python3
"""Construit `app/assets/data/quran_search_index_warsh.json` -- l'index de
recherche du « Shazam coranique » et du suivi de priere, pour le texte Warsh.

Meme forme que l'index Hafs existant : {"verses":[{"s":1,"a":1,"w":[mots]}]}.
Les mots sont normalises EXACTEMENT comme `ArabicNormalizer.normalize()` cote
Dart (squelette sans harakat) -- c'est indispensable : la requete est la
sortie du modele ASR, comparee a ce meme format. Toute divergence entre les
deux normalisations rendrait l'index muet sans le moindre message d'erreur.

⚠️ Si `ArabicNormalizer._collapseVariants` change cote Dart, ce fichier doit
changer avec lui. La regle du YEH BARREE (U+06D2 -> ya) ajoutee le 2026-08-12
est deja repercutee ici.

Usage : python3 build_warsh_search_index.py
"""
import json
import re
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SOURCE = RACINE / "app" / "assets" / "data" / "quran_verses_warsh.json"
SORTIE = RACINE / "app" / "assets" / "data" / "quran_search_index_warsh.json"

# Classe `_harakat` du Dart : [ً-ٰٟؐ-ؚۖ-ۭـ]
HARAKAT = re.compile("[ً-ٰٟؐ-ؚۖ-ۭـ]")

# `_collapseVariants`, dans le meme ORDRE qu'en Dart (l'ordre compte : le
# dagger alif doit devenir un alif AVANT le retrait des harakat).
ETAPE1 = [
    ("ٱ", "ا"),   # alif wasla
    ("وٰ", "ا"),  # rasm ancien a waw muet
    ("ٰ", "ا"),   # dagger alif
    ("ۥ", "و"),   # petit waw
    ("ۦ", "ي"),   # petit yeh
    ("ٔ", "ء"),   # hamza suscrite combinante
    ("ٓ", ""),    # maddah combinante
    ("ـ", ""),    # tatweel
    ("۞", ""),    # rub el hizb
    ("۩", ""),    # sajda
    ("ے", "ى"),  # YEH BARREE (script Warsh) -> ya sans points
]
ETAPE2 = [("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ى", "ي"),
          ("ؤ", "و"), ("ئ", "ي"), ("ة", "ه")]


def normalize(t: str) -> str:
    for a, b in ETAPE1:
        t = t.replace(a, b)
    for a, b in ETAPE2:
        t = t.replace(a, b)
    t = re.sub(r"[^؀-ۿ\s]", "", t)
    t = HARAKAT.sub("", t)
    return re.sub(r"\s+", " ", t).strip()


def main():
    versets = json.loads(SOURCE.read_text(encoding="utf-8"))
    sortie = []
    vides = []
    for v in versets:
        s, a = v["verse_key"].split(":")
        mots = [m for m in (normalize(w) for w in v["text_uthmani"].split()) if m]
        if not mots:
            vides.append(v["verse_key"])
        sortie.append({"s": int(s), "a": int(a), "w": mots})

    SORTIE.write_text(json.dumps({"verses": sortie}, ensure_ascii=False),
                      encoding="utf-8")
    total = sum(len(v["w"]) for v in sortie)
    print(f"versets indexes : {len(sortie)}")
    print(f"mots indexes    : {total}")
    print(f"versets vides   : {len(vides)} {vides[:5]}")
    print(f"-> {SORTIE}  ({SORTIE.stat().st_size / 1e6:.2f} Mo)")
    if vides:
        raise SystemExit("ECHEC : un verset sans aucun mot indexable.")


if __name__ == "__main__":
    main()
