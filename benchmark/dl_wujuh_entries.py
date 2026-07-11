"""
Telecharge et decoupe en ENTREES PRECISES (une par racine/mot) les deux ouvrages
dedies a al-wujuh wal-naza'ir + le lexique des nuances :
  - Mufradat (Ar-Raghib al-Isfahani)     : une entree par racine
  - Nuzhat al-A'yun (Ibn al-Jawzi)       : une entree par mot (baab)

Contrairement a dl_turath_ulum_quran.py (qui sauvait le texte nettoye page par page),
ce script garde le HTML brut le temps de reperer les balises
<span data-type="title" id=toc-N>TITRE</span> qui marquent le DEBUT EXACT de chaque
entree dans le flux de lecture. C'est indispensable : une recherche de sous-chaine
naive sur le titre ("أبى" par ex.) matche a tort dans des notes de bas de page qui
citent un AUTRE dictionnaire (verifie sur un cas reel) -> melange de sens entre mots.
Ancrer sur la balise structurelle elimine ce risque.

Sortie : data/quran_sciences/{slug}_entries.jsonl
  {"heading": "...", "text": "...", "page_start": N, "page_end": N}
"""
import truststore; truststore.inject_into_ssl()
import json, re, urllib.request, time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = Path(__file__).parent
OUT_DIR = ROOT / "data" / "quran_sciences"
OUT_DIR.mkdir(parents=True, exist_ok=True)

API = "https://api.turath.io/page"
WORKERS = 12

BOOKS = {
    # slug          book_id  pg_lo pg_hi  skip_heading_prefixes (section dividers, pas des entrees)
    "ar-mufradat":     (23636, 39, 878,  ["كتاب "]),
    "ar-nuzhat-ayun":  (6334,   1, 565,  []),
}

TITLE_RE = re.compile(r'<span data-type="title"[^>]*>(.*?)</span>', re.S)


def strip_tags(t):
    t = re.sub(r"<[^>]+>", " ", t)
    return re.sub(r"[ \t]+", " ", t).strip()


def fetch_raw_page(book_id, pg):
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
                return pg, meta or {}, obj.get("text", "") or ""
        except Exception:
            time.sleep(1 + i)
    return pg, {}, ""


def build_entries(slug, book_id, pg_lo, pg_hi, skip_prefixes):
    out_path = OUT_DIR / f"{slug}_entries.jsonl"
    if out_path.exists() and out_path.stat().st_size > 5000:
        print(f"  {slug}: deja present, skip", flush=True)
        return 0

    pages = {}
    done = 0
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futs = {ex.submit(fetch_raw_page, book_id, pg): pg for pg in range(pg_lo, pg_hi + 1)}
        for fut in as_completed(futs):
            pg, meta, raw = fut.result()
            pages[pg] = (meta, raw)
            done += 1
            if done % 200 == 0:
                print(f"    {slug}: fetch {done}/{pg_hi - pg_lo + 1}", flush=True)

    # Parcours sequentiel : split chaque page sur les balises <span title>,
    # l'entree ouverte se poursuit sur les pages suivantes tant qu'aucun nouveau titre n'apparait.
    entries = []  # each: {heading, parts: [text...], page_start, page_end}
    current = None
    for pg in range(pg_lo, pg_hi + 1):
        if pg not in pages:
            continue
        meta, raw = pages[pg]
        pieces = TITLE_RE.split(raw)
        # re.split with a capturing group returns [pre, title1, mid1, title2, mid2, ...]
        pre = pieces[0]
        if current is not None and pre.strip():
            current["parts"].append(pre)
            current["page_end"] = pg
        for i in range(1, len(pieces), 2):
            title = strip_tags(pieces[i]).strip()
            body = pieces[i + 1] if i + 1 < len(pieces) else ""
            if current is not None:
                entries.append(current)
            current = {"heading": title, "parts": [body], "page_start": pg, "page_end": pg,
                       "is_entry": not any(title.startswith(p) for p in skip_prefixes)}
    if current is not None:
        entries.append(current)

    n = 0
    with open(out_path, "w", encoding="utf-8") as f:
        for e in entries:
            if not e["is_entry"]:
                continue
            text = strip_tags("".join(e["parts"]))
            if len(text) < 5:
                continue
            f.write(json.dumps({
                "heading": e["heading"],
                "text": text,
                "page_start": e["page_start"],
                "page_end": e["page_end"],
            }, ensure_ascii=False) + "\n")
            n += 1
    print(f"  -> {out_path.name} ({n} entrees)", flush=True)
    return n


def main():
    total = 0
    for slug, (book_id, pg_lo, pg_hi, skip_prefixes) in BOOKS.items():
        print(f"=== {slug} (book_id={book_id}, pages {pg_lo}-{pg_hi}) ===", flush=True)
        try:
            total += build_entries(slug, book_id, pg_lo, pg_hi, skip_prefixes)
        except Exception as e:
            print(f"  ECHEC {slug}: {e}", flush=True)
    print(f"\nTOTAL entrees: {total}", flush=True)
    print("WUJUH ENTRIES DONE", flush=True)


if __name__ == "__main__":
    main()
