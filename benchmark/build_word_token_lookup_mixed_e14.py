"""
Variante de build_word_token_lookup_tajweed.py pour le checkpoint epoch14 du
run "tajweed-mixed" (cf. ckpt_to_nemo_epoch14.py / export_ckpt_to_onnx.py,
2026-07-18) -- meme tokenizer/logique que la version tajweed (normalize_training
identique, text_to_ids SANS prefixe manuel), juste un snapshot/dossier de
sortie differents.
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import json, re, time
from pathlib import Path
import requests
import nemo.collections.asr as nemo_asr

BASE_DIR      = Path(__file__).parent
NEMO_SNAPSHOT = BASE_DIR / "models" / "fastconformer-quran-tajweed-mixed" / "mixed-e14-snapshot.nemo"
DEPLOY_DIR    = BASE_DIR / "models" / "fastconformer-quran-tajweed-mixed" / "deploy"
OUT_JSON      = DEPLOY_DIR / "word_tokens.json"

QURAN_API     = "https://api.quran.com/api/v4"


def normalize_training(text: str) -> str:
    t = text.replace("۞", "").replace("﻿", "")
    return re.sub(r"\s+", " ", t).strip()


def fetch_all_quran_words() -> set[str]:
    words = set()
    session = requests.Session()
    for surah in range(1, 115):
        for attempt in range(3):
            try:
                r = session.get(
                    f"{QURAN_API}/verses/by_chapter/{surah}",
                    params={"fields": "text_uthmani", "per_page": 286},
                    timeout=20,
                )
                r.raise_for_status()
                break
            except Exception as e:
                if attempt == 2:
                    raise
                print(f"  [retry] sourate {surah}: {e}")
                time.sleep(2)
        verses = r.json()["verses"]
        for v in verses:
            text = v["text_uthmani"]
            for w in text.split():
                norm = normalize_training(w)
                if norm:
                    words.add(norm)
        print(f"  Sourate {surah:3d} : {len(verses):3d} versets — {len(words)} mots uniques cumules")
    return words


def main():
    print("Telechargement du texte coranique (api.quran.com, 114 sourates)...")
    words = fetch_all_quran_words()
    print(f"\nTotal mots uniques (normalize_training) : {len(words)}")

    print(f"\nChargement du tokenizer NeMo : {NEMO_SNAPSHOT}")
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        str(NEMO_SNAPSHOT), map_location="cpu")
    tok = model.tokenizer

    print("Tokenisation de chaque mot (SentencePiece reel, SANS prefixe manuel)...")
    lookup: dict[str, list[int]] = {}
    unk_count = 0
    for w in sorted(words):
        ids = tok.text_to_ids(w)
        lookup[w] = ids
        if not ids:
            unk_count += 1
            print(f"  [WARN] tokenisation vide pour \"{w}\"")

    print(f"\nMots tokenises : {len(lookup)} | vides/suspects : {unk_count}")

    DEPLOY_DIR.mkdir(parents=True, exist_ok=True)
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(lookup, f, ensure_ascii=False)

    size_kb = OUT_JSON.stat().st_size / 1024
    print(f"\nLookup ecrit : {OUT_JSON} ({size_kb:.0f} Ko)")


if __name__ == "__main__":
    main()
