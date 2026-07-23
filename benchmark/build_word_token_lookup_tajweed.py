"""
Variante de build_word_token_lookup.py pour le modèle CTC tajweed (au lieu
de pcd). Deux corrections par rapport au script d'origine, toutes deux
vérifiées empiriquement le 2026-07-14 :

1. normalize_training() ici DOIT matcher la version CORRIGÉE de
   ArabicNormalizer.normalizeTraining() (app/lib/services/recitation_verifier.dart,
   fix 2026-07-14) — qui ne retire plus que le rub el hizb (۞) et le BOM,
   PAS wasla/dagger alif/tatweel/waqf comme l'ancienne version pcd-only.
   Bug confirmé sur audio réel : l'ancienne normalisation transformait
   "ٱللَّهِ" (1 token correct côté corpus, id 114) en "اللَّهِ" (4 tokens sans
   rapport, [955,964,957,279]) — alignement forcé cassé dès le 2e mot de
   toute récitation contenant l'article défini ٱل (wasla).

2. text_to_ids() est appelé SANS préfixer manuellement "▁" — vérifié que
   `tok.text_to_ids("▁" + mot)` insère un token "▁" isolé parasite en tête
   (id 955 pour ce tokenizer tajweed) qui n'apparaît JAMAIS dans la
   tokenisation réelle du corpus (ni mot isolé ni phrase complète). Sur pcd,
   les deux formes coïncidaient (d'où le bug invisible jusqu'ici) ; sur
   tajweed elles divergent sur 100% des mots testés. `tok.text_to_ids(mot)`
   seul (sans préfixe) est la forme qui correspond à la tokenisation
   utilisée à l'entraînement.
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
NEMO_SNAPSHOT = BASE_DIR / "models" / "fastconformer-quran-tajweed" / "fastconformer-quran-best.nemo"
DEPLOY_DIR    = BASE_DIR / "models" / "fastconformer-quran-tajweed" / "deploy" / "fastconformer-ctc-tajweed"
OUT_JSON      = DEPLOY_DIR / "word_tokens.json"

QURAN_API     = "https://api.quran.com/api/v4"


# ─── Normalisation IDENTIQUE à ArabicNormalizer.normalizeTraining (Dart, fix 2026-07-14) ───
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
        print(f"  Sourate {surah:3d} : {len(verses):3d} versets — {len(words)} mots uniques cumulés")
    return words


def main():
    print("Téléchargement du texte coranique (api.quran.com, 114 sourates)...")
    words = fetch_all_quran_words()
    print(f"\nTotal mots uniques (normalize_training) : {len(words)}")

    print(f"\nChargement du tokenizer NeMo : {NEMO_SNAPSHOT}")
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        str(NEMO_SNAPSHOT), map_location="cpu")
    tok = model.tokenizer

    print("Tokenisation de chaque mot (SentencePiece réel, SANS préfixe manuel)...")
    lookup: dict[str, list[int]] = {}
    unk_count = 0
    for w in sorted(words):
        ids = tok.text_to_ids(w)
        lookup[w] = ids
        if not ids:
            unk_count += 1
            print(f"  [WARN] tokenisation vide pour \"{w}\"")

    print(f"\nMots tokenisés : {len(lookup)} | vides/suspects : {unk_count}")

    DEPLOY_DIR.mkdir(parents=True, exist_ok=True)
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(lookup, f, ensure_ascii=False)

    size_kb = OUT_JSON.stat().st_size / 1024
    print(f"\nLookup écrit : {OUT_JSON} ({size_kb:.0f} Ko)")


if __name__ == "__main__":
    main()
