"""
Telecharge des ouvrages classiques d'ulum al-Qur'an centres sur al-wujuh wal-naza'ir
(pourquoi ce mot precis et pas un synonyme), via l'API turath.io (page par page,
livres entiers, pas des tafsirs par verset).
Sauvegarde brute paginee dans data/quran_sciences/{slug}.jsonl (un objet par page).

Cibles (IDs turath.io confirmes par recherche + test de fetch reel) :
  - 11728 -> ar-itqan       : al-Itqan fi Ulum al-Qur'an, As-Suyuti
                              (chapitre dedie: al-wujuh wal-naza'ir)
  - 11436 -> ar-burhan      : al-Burhan fi Ulum al-Qur'an, Az-Zarkashi (idem)
  - 6334  -> ar-nuzhat-ayun : Nuzhat al-A'yun an-Nawazir fi 'Ilm al-Wujuh wal-Naza'ir,
                              Ibn al-Jawzi — LE traite le plus dedie a ce sujet precis
  - 23636 -> ar-mufradat    : al-Mufradat fi Gharib al-Qur'an, Ar-Raghib al-Isfahani
                              (lexique des nuances, organise par racine)
"""
import truststore; truststore.inject_into_ssl()
import json, re, urllib.request, time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = Path(__file__).parent
OUT_DIR = ROOT / "data" / "quran_sciences"
OUT_DIR.mkdir(parents=True, exist_ok=True)

API = "https://api.turath.io/page"

BOOKS = {
    11728: ("ar-itqan", 1459),
    11436: ("ar-burhan", 1944),
    6334:  ("ar-nuzhat-ayun", 565),
    23636: ("ar-mufradat", 881),
}

WORKERS = 12


def clean(t):
    if not t:
        return ""
    t = re.sub(r"<span[^>]*>", "", t)
    t = re.sub(r"</span>", "", t)
    t = re.sub(r"<[^>]+>", " ", t)
    return re.sub(r"[ \t]+", " ", t).strip()


def fetch_page(book_id, pg):
    url = f"{API}?book_id={book_id}&pg={pg}&ver=3"
    for i in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0", "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=30) as r:
                obj = json.loads(r.read().decode("utf-8"))
                meta = obj.get("meta")
                if isinstance(meta, str):
                    try:
                        meta = json.loads(meta)
                    except Exception:
                        meta = {}
                return pg, meta or {}, clean(obj.get("text", ""))
        except Exception:
            time.sleep(1 + i)
    return pg, {}, ""


def download_book(book_id, slug, n_pages):
    out_path = OUT_DIR / f"{slug}.jsonl"
    if out_path.exists() and out_path.stat().st_size > 10000:
        print(f"  {slug}: deja present, skip", flush=True)
        return 0

    results = {}
    done = 0
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futs = {ex.submit(fetch_page, book_id, pg): pg for pg in range(1, n_pages + 1)}
        for fut in as_completed(futs):
            pg, meta, text = fut.result()
            if text:
                results[pg] = (meta, text)
            done += 1
            if done % 200 == 0:
                print(f"    {slug}: {done}/{n_pages}", flush=True)

    n = 0
    with open(out_path, "w", encoding="utf-8") as f:
        for pg in range(1, n_pages + 1):
            if pg in results:
                meta, text = results[pg]
                f.write(json.dumps({
                    "page_id": pg,
                    "vol": meta.get("vol"),
                    "page": meta.get("page"),
                    "headings": meta.get("headings", []),
                    "text": text,
                }, ensure_ascii=False) + "\n")
                n += 1
    print(f"  -> {out_path.name} ({n}/{n_pages} pages)", flush=True)
    return n


def main():
    print(f"Ouvrages a telecharger: {[s for s, _ in BOOKS.values()]}", flush=True)
    total = 0
    for book_id, (slug, n_pages) in BOOKS.items():
        print(f"\n=== {slug} (book_id={book_id}, {n_pages} pages) ===", flush=True)
        try:
            total += download_book(book_id, slug, n_pages)
        except Exception as e:
            print(f"  ECHEC {slug}: {e}", flush=True)
    print(f"\nTOTAL pages: {total}", flush=True)
    print("TURATH ULUM AL-QURAN DOWNLOAD DONE", flush=True)


if __name__ == "__main__":
    main()
