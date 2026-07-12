"""
Construit l'index mot -> racine, par verset, a partir de ar-tahlil-kalimat.jsonl
(deja une decomposition mot-par-mot du Coran, avec racine grammaticale quand
elle existe). Necessaire pour la fonctionnalite "tap sur un mot" : l'app tape
le mot a la position N du verset, on a besoin de savoir a quelle racine ca
correspond pour chercher dans Mufradat/Nuzhat al-Ayun.

Format de ar-tahlil-kalimat : une puce "• " par mot affiche a l'ecran, les
morphemes du mot entre ﴿...﴾, la racine indiquee par "من مادّة X" si le mot
est un contenu lexical (pas pour les particules/pronoms : حرف جر، ضمير،
اسم موصول... qui n'ont pas de racine, note root=None).

Sortie : data/quran_sciences/word_root_index.jsonl
  {"verse_key": "s:a", "words": [{"surface": "...", "root": "..." | null}, ...]}
"""
import json, re
from pathlib import Path

ROOT = Path(__file__).parent
SRC = ROOT / "data" / "tafsir" / "ar-tahlil-kalimat.jsonl"
OUT = ROOT / "data" / "quran_sciences" / "word_root_index.jsonl"

ROOT_RE = re.compile(r"من\s+مادّة\s+(\S+)")
BRACKET_RE = re.compile(r"﴿([^﴾]+)﴾")


def parse_verse(text):
    bullets = [b.strip() for b in text.split("\n") if b.strip().startswith("•")]
    words = []
    for b in bullets:
        b = b[1:].strip()
        surfaces = BRACKET_RE.findall(b)
        if not surfaces:
            continue
        root_m = ROOT_RE.search(b)
        root = root_m.group(1).strip(" ،.:؛") if root_m else None
        words.append({"surface": "".join(surfaces), "root": root})
    return words


def main():
    n = 0
    with_root = 0
    with open(SRC, encoding="utf-8") as f, open(OUT, "w", encoding="utf-8") as out:
        for l in f:
            o = json.loads(l)
            words = parse_verse(o["text"])
            if not words:
                continue
            out.write(json.dumps({"verse_key": o["verse_key"], "words": words}, ensure_ascii=False) + "\n")
            n += 1
            with_root += sum(1 for w in words if w["root"])
    print(f"{n} versets indexes -> {OUT}", flush=True)
    print(f"mots avec racine identifiee : {with_root}", flush=True)


if __name__ == "__main__":
    main()
