"""Telecharge le texte coranique annote tajweed (les 17 classes de regles)
depuis l'API quran.com — Phase 0.1 du PLAN_ENTRAINEMENT_HYBRIDE.md.

Deux champs par verset :
  - text_uthmani          : texte canonique (SOURCE DE VERITE des caracteres)
  - text_uthmani_tajweed  : texte avec balises <tajweed class=X>...</tajweed>
                            (SOURCE DES POSITIONS/CLASSES uniquement — piege
                            documente : 4278/6236 versets ont des caracteres
                            differents du canonique, ex. dagger alif remplace
                            par U+0672 — ne JAMAIS entrainer sur ses caracteres)

Sortie : data/quran_tajweed_rules/uthmani.jsonl + uthmani_tajweed.jsonl
         ({"verse_key": "s:a", "text": "..."} par ligne)
"""
import json
import time
import urllib.request
from pathlib import Path

BASE = Path(__file__).parent
OUT_DIR = BASE / "data" / "quran_tajweed_rules"
OUT_DIR.mkdir(parents=True, exist_ok=True)

API = "https://api.quran.com/api/v4/quran/verses/{script}?chapter_number={ch}"


def fetch(script: str, ch: int, retries: int = 5):
    url = API.format(script=script, ch=ch)
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "CoranKarim/1.0"})
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)["verses"]
        except Exception as e:
            wait = 2 ** attempt
            print(f"  retry {script} ch{ch} dans {wait}s ({e})", flush=True)
            time.sleep(wait)
    raise SystemExit(f"ECHEC definitif : {url}")


def main():
    for script, field, fname in [
        ("uthmani", "text_uthmani", "uthmani.jsonl"),
        ("uthmani_tajweed", "text_uthmani_tajweed", "uthmani_tajweed.jsonl"),
    ]:
        out = OUT_DIR / fname
        if out.exists():
            n = sum(1 for _ in open(out, encoding="utf-8"))
            if n == 6236:
                print(f"{fname} deja complet ({n} versets) — skip")
                continue
        rows = []
        for ch in range(1, 115):
            verses = fetch(script, ch)
            for v in verses:
                rows.append({"verse_key": v["verse_key"], "text": v[field]})
            print(f"  {script} ch{ch:3d}/114 — cumul {len(rows)}", flush=True)
            time.sleep(0.3)  # politesse API
        assert len(rows) == 6236, f"{script}: {len(rows)} versets != 6236"
        with open(out, "w", encoding="utf-8") as f:
            for r in rows:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
        print(f"OK {out} ({len(rows)} versets)")


if __name__ == "__main__":
    main()
