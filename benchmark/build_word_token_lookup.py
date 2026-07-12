"""
Précalcule le dictionnaire mot -> IDs de tokens BPE avec le VRAI tokenizer
NeMo (SentencePiece), pour l'alignement forcé CTC (cf. ForcedAligner.kt,
CtcTokenizer.kt côté app). Remplace la réimplémentation heuristique
"greedy longest-match" par la vérité terrain — élimine tout risque de
divergence entre la tokenisation utilisée pour l'alignement et celle
réellement apprise par le modèle (constaté 2026-07-11 : les deux coïncidaient
sur les mots testés, mais rien ne garantit que ça reste vrai pour tout le
Coran — mieux vaut ne jamais avoir à se poser la question).

IMPORTANT : la normalisation appliquée ICI doit être EXACTEMENT identique à
ArabicNormalizer.normalizeTraining() côté Dart (app/lib/services/
recitation_verifier.dart) — c'est cette forme, PAS normalizeStrict (qui
fusionne أ/إ/آ/ى/ؤ/ئ/ة), qui est envoyée à setAlignmentTarget(). Si l'une
des deux normalisations dérive de l'autre, ce lookup devient incorrect.

Source du texte : api.quran.com (même API et mêmes champs que
app/lib/services/quran_api.dart : text_uthmani, per_page=286) — pas le
manifest d'entraînement (qui mélange Coran + Arabic Speech Corpus depuis
l'augmentation 2026-07-10, et n'est pas garanti de couvrir 100% du texte
canonique verset par verset).

Usage:
    "D:/Coran Karim/benchmark/.venv/Scripts/python.exe" -X utf8 build_word_token_lookup.py
Sortie:
    benchmark/models/fastconformer-quran-pcd/onnx_export/deploy/fastconformer-ctc-pcd/word_tokens.json
    (même dossier de déploiement que vocab.json — à pousser sur l'appareil
    de la même façon)
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

BASE_DIR    = Path(__file__).parent
NEMO_SNAPSHOT = BASE_DIR / "models" / "fastconformer-quran-pcd" / "fastconformer-quran-pcd-snapshot.nemo"
DEPLOY_DIR  = BASE_DIR / "models" / "fastconformer-quran-pcd" / "onnx_export" / "deploy" / "fastconformer-ctc-pcd"
OUT_JSON    = DEPLOY_DIR / "word_tokens.json"

QURAN_API   = "https://api.quran.com/api/v4"


# ─── Normalisation IDENTIQUE à ArabicNormalizer.normalizeTraining (Dart) ─────
_ANNOTATION_MARKS = re.compile(r"[ؖ-ؚۖ-ۜ۟-۪ۤۧۨ-ۭ]")
_PUNCT = re.compile(r"""[،؛؟.,!?:;\-_()\[\]{}"'»«]""")
_WS = re.compile(r"\s+")


def normalize_training(text: str) -> str:
    t = text
    t = t.replace("ٱ", "ا")
    t = t.replace("وٰ", "ا")
    t = t.replace("ٰ", "ا")
    t = t.replace("ۥ", "و")
    t = t.replace("ۦ", "ي")
    t = t.replace("ٔ", "ء")
    t = t.replace("ٓ", "")
    t = t.replace("ـ", "")
    t = t.replace("۞", "")
    t = t.replace("۩", "")
    t = _ANNOTATION_MARKS.sub("", t)
    t = _PUNCT.sub("", t)
    return _WS.sub(" ", t).strip()


def fetch_all_quran_words() -> set[str]:
    """Récupère le texte de toutes les sourates (1-114), retourne l'ensemble
    des mots uniques après normalize_training (identique à splitExpectedWords
    + normalizeTraining côté app)."""
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

    print("Tokenisation de chaque mot (SentencePiece réel, préfixe ▁)...")
    lookup: dict[str, list[int]] = {}
    unk_count = 0
    for w in sorted(words):
        ids = tok.text_to_ids("▁" + w)
        lookup[w] = ids
        # Vérif grossière : un id hors vocabulaire (>= taille vocab) signalerait
        # un problème de tokenizer -- ne devrait jamais arriver avec SentencePiece
        # (BPE se rabat toujours sur des pièces plus courtes, jusqu'au caractère).
        if not ids:
            unk_count += 1
            print(f"  [WARN] tokenisation vide pour \"{w}\"")

    print(f"\nMots tokenisés : {len(lookup)} | vides/suspects : {unk_count}")

    DEPLOY_DIR.mkdir(parents=True, exist_ok=True)
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(lookup, f, ensure_ascii=False)

    size_kb = OUT_JSON.stat().st_size / 1024
    print(f"\nLookup écrit : {OUT_JSON} ({size_kb:.0f} Ko)")
    print("\nÉtape suivante : pousser word_tokens.json sur l'appareil, à côté de")
    print("vocab.json (même convention de déploiement, cf. FastConformerVerifier).")


if __name__ == "__main__":
    main()
