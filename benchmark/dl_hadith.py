"""
Telecharge les 6 livres canoniques de hadith (fawazahmed0/hadith-api).
Pour chaque collection : Arabe (avec grades d'authenticite) + Francais (ou Anglais
si FR absent). Fusionne par numero de hadith.

Sortie : data/islamic_corpus/hadith/{collection}.jsonl
Chaque ligne :
  {
    "collection": "bukhari",
    "number": 1,
    "ar": "<texte arabe>",
    "fr": "<traduction FR ou EN>",
    "fr_lang": "fr" | "en",
    "grades": [{"name": "...", "grade": "..."}],
    "reference": {"book": x, "hadith": y},
    "source": "Sahih al-Bukhari 1"
  }

Conserve les metadonnees (grade, reference, source) => RAG-ready + citation.
"""
import truststore; truststore.inject_into_ssl()
import json, os, urllib.request, time
from pathlib import Path

ROOT    = Path(__file__).parent
OUT_DIR = ROOT / "data" / "islamic_corpus" / "hadith"
OUT_DIR.mkdir(parents=True, exist_ok=True)

BASE = "https://cdn.jsdelivr.net/gh/fawazahmed0/hadith-api@1/editions"

# collection -> (slug AR avec grades, slug traduction, lang traduction, nom affiche)
COLLECTIONS = {
    "bukhari":  ("ara-bukhari",  "fra-bukhari",  "fr", "Sahih al-Bukhari"),
    "muslim":   ("ara-muslim",   "fra-muslim",   "fr", "Sahih Muslim"),
    "abudawud": ("ara-abudawud", "fra-abudawud", "fr", "Sunan Abu Dawud"),
    "tirmidhi": ("ara-tirmidhi", "eng-tirmidhi", "en", "Jami at-Tirmidhi"),  # pas de FR
    "nasai":    ("ara-nasai",    "fra-nasai",    "fr", "Sunan an-Nasa'i"),
    "ibnmajah": ("ara-ibnmajah", "fra-ibnmajah", "fr", "Sunan Ibn Majah"),
}


def fetch_json(url, retries=3):
    last = None
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception as e:
            last = e
            time.sleep(2 * (i + 1))
    raise last


def index_by_number(book_json):
    out = {}
    for h in book_json.get("hadiths", []):
        out[h.get("hadithnumber")] = h
    return out


def main():
    total = 0
    for coll, (ar_slug, tr_slug, tr_lang, display) in COLLECTIONS.items():
        print(f"\n=== {coll} ({display}) ===", flush=True)
        try:
            ar_book = fetch_json(f"{BASE}/{ar_slug}.json")
            print(f"  AR: {len(ar_book.get('hadiths', []))} hadiths", flush=True)
        except Exception as e:
            print(f"  ECHEC AR: {e}", flush=True)
            continue

        try:
            tr_book = fetch_json(f"{BASE}/{tr_slug}.json")
            print(f"  {tr_lang.upper()}: {len(tr_book.get('hadiths', []))} hadiths", flush=True)
            tr_idx = index_by_number(tr_book)
        except Exception as e:
            print(f"  (traduction indisponible: {e})", flush=True)
            tr_idx = {}

        out_path = OUT_DIR / f"{coll}.jsonl"
        n = 0
        with open(out_path, "w", encoding="utf-8") as f:
            for h in ar_book.get("hadiths", []):
                num = h.get("hadithnumber")
                tr  = tr_idx.get(num, {})
                entry = {
                    "collection": coll,
                    "number":     num,
                    "ar":         (h.get("text") or "").strip(),
                    "fr":         (tr.get("text") or "").strip(),
                    "fr_lang":    tr_lang if tr else None,
                    "grades":     h.get("grades", []),
                    "reference":  h.get("reference", {}),
                    "source":     f"{display} {num}",
                }
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
                n += 1
        print(f"  -> {out_path.name} ({n} hadiths)", flush=True)
        total += n

    print(f"\nTOTAL hadiths: {total}", flush=True)
    print("HADITH DOWNLOAD DONE", flush=True)


if __name__ == "__main__":
    main()
