"""
Construit un index offset (verse_key -> [offset_octets, longueur_octets]) pour
chaque gros fichier JSONL de data/quran_sciences/ (ayah_explanations.jsonl,
word_explanations.jsonl) -- ces fichiers (128/177 Mo) sont trop volumineux
pour etre charges entierement en RAM cote mobile (contrainte 6 Go RAM,
cf. .claude/skills/model-training/references/asr.md), donc l'app doit faire
des lectures a acces direct (RandomAccessFile.read a un offset precis) plutot
que tout parser au demarrage.

Usage:
    "D:/Coran Karim/benchmark/.venv/Scripts/python.exe" -X utf8 build_explanation_offset_index.py
Sortie (a cote des .jsonl sources) :
    ayah_explanations.offsets.json
    word_explanations.offsets.json
"""
import json
from pathlib import Path

BASE_DIR = Path(__file__).parent / "data" / "quran_sciences"


def build_index(jsonl_name: str, out_name: str):
    src = BASE_DIR / jsonl_name
    out = BASE_DIR / out_name
    index = {}
    offset = 0
    with open(src, "rb") as f:
        for raw_line in f:
            length = len(raw_line)
            # Parse juste pour extraire verse_key (les octets bruts restent la
            # source de verite pour la relecture -- pas de re-encodage ici).
            try:
                obj = json.loads(raw_line)
                key = obj["verse_key"]
                index[key] = [offset, length]
            except Exception as e:
                print(f"  [WARN] ligne illisible a l'offset {offset} : {e}")
            offset += length
    with open(out, "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False)
    print(f"{jsonl_name} : {len(index)} entrees -> {out.name} "
          f"({out.stat().st_size/1024:.0f} Ko)")


def main():
    build_index("ayah_explanations.jsonl", "ayah_explanations.offsets.json")
    build_index("word_explanations.jsonl", "word_explanations.offsets.json")


if __name__ == "__main__":
    main()
