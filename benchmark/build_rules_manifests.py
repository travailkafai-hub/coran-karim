"""Manifests du run hybride "vrai tajweed" (Phase 0.5 du plan) :
  1. Remap des chemins audio vers CETTE machine (tout est sur le SSD local,
     verifie le 2026-07-19 : train_wav_local couvre 100% des clips Coran).
  2. Annotation des clips CORAN avec les symboles de regles (via verse_key
     extrait du nom de fichier {surah}_{ayah}.wav + verification du texte).
     ASC et TTS gardent leur texte tel quel (pas de symboles — contre-exemples).

Sorties : nemo_manifests_rules/{train,val}_manifest.jsonl (+ stats affichees).
"""
import json
import re
from pathlib import Path

BASE = Path(__file__).parent
SRC_DIR = BASE / "nemo_manifests_mixed"
OUT_DIR = BASE / "nemo_manifests_rules"
OUT_DIR.mkdir(exist_ok=True)

RULES_DIR = BASE / "data" / "quran_tajweed_rules"

REMAPS = [
    ("/mnt/ssd5/Coran Karim/benchmark/", str(BASE) + "/"),
    ("/mnt/hdd/Coran Karim/benchmark/data/train_wav/",
     str(BASE / "data" / "train_wav_local") + "/"),
]

VERSE_RE = re.compile(r"/(\d{1,3})_(\d{1,3})\.wav$")


def norm(s: str) -> str:
    """Meme normalisation que le pipeline mixed : retire ۞, espaces normalises."""
    return " ".join(s.replace("۞", " ").split())


def main():
    annotated = {}
    canonical = {}
    for l in open(RULES_DIR / "annotated.jsonl", encoding="utf-8"):
        r = json.loads(l)
        annotated[r["verse_key"]] = norm(r["text"])
    for l in open(RULES_DIR / "uthmani.jsonl", encoding="utf-8"):
        r = json.loads(l)
        canonical[r["verse_key"]] = norm(r["text"])

    for src_name, out_name in [
        ("train_mixed.jsonl", "train_manifest.jsonl"),
        ("val_mixed.jsonl", "val_manifest.jsonl"),
    ]:
        stats = {"quran_annotated": 0, "quran_prefix": 0, "quran_mismatch": 0,
                 "non_quran": 0, "missing_audio": 0}
        rows_out = []
        for l in open(SRC_DIR / src_name, encoding="utf-8"):
            r = json.loads(l)
            p = r["audio_filepath"]
            for old, new in REMAPS:
                if p.startswith(old):
                    p = new + p[len(old):]
                    break
            if not Path(p).exists():
                stats["missing_audio"] += 1
                continue
            r["audio_filepath"] = p

            # "/train_wav_local/" = ancien remap SSD ; "/train_wav/" = chemin
            # HDD actuel (/run/media/kafai/HDD/... depuis le fix 2026-07-19
            # de build_mixed_manifest.py) -- les deux designent les clips
            # Coran, jamais ASC/TTS (noms de fichiers differents).
            m = VERSE_RE.search(p) if ("/train_wav_local/" in p or "/train_wav/" in p) else None
            if m:
                key = f"{int(m.group(1))}:{int(m.group(2))}"
                canon = canonical.get(key)
                ann = annotated.get(key)
                text = norm(r["text"])
                if canon and ann:
                    if text == canon:
                        r["text"] = ann
                        stats["quran_annotated"] += 1
                    elif text.endswith(canon):
                        # prefixe (bismillah recitee en tete) conserve tel quel,
                        # seule la partie verset est annotee
                        r["text"] = text[: -len(canon)] + ann
                        stats["quran_prefix"] += 1
                    else:
                        stats["quran_mismatch"] += 1  # texte garde sans symboles
                else:
                    stats["quran_mismatch"] += 1
            else:
                stats["non_quran"] += 1
            rows_out.append(r)

        out = OUT_DIR / out_name
        with open(out, "w", encoding="utf-8") as f:
            for r in rows_out:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
        print(f"{out.name}: {len(rows_out)} lignes — {stats}")


if __name__ == "__main__":
    main()
