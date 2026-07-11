"""
Telecharge les tafsirs classiques manquants (spa5k/tafsir_api), per-ayah, threade.
Sauvegarde au meme format que les tafsirs existants : {"verse_key": "s:a", "text": "..."}
dans data/tafsir/{slug}.jsonl

Cibles (deja presents: ar-ibn-kathir, ar-saadi, ar-muyassar, en-ibn-kathir, en-maarif,
fr-hamidullah, fr-montada, fr-rashid-maash) :
  - ar-tafsir-al-tabari      (Tabari, le plus ancien)
  - ar-tafseer-al-qurtubi    (Qurtubi, fiqh)
  - ar-tafsir-al-jalalayn    (Jalalayn, concis)
  - ar-tafsir-al-baghawi     (Baghawi)
  - french-mokhtasar         (seul tafsir FR complet dispo)
"""
import truststore; truststore.inject_into_ssl()
import json, os, urllib.request, time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT    = Path(__file__).parent
OUT_DIR = ROOT / "data" / "tafsir"
OUT_DIR.mkdir(parents=True, exist_ok=True)

BASE = "https://cdn.jsdelivr.net/gh/spa5k/tafsir_api@main/tafsir"

# slug distant -> nom de fichier local
TARGETS = {
    "ar-tafsir-al-tabari":   "ar-tabari",
    "ar-tafseer-al-qurtubi": "ar-qurtubi",
    "ar-tafsir-al-jalalayn": "ar-jalalayn",
    "ar-tafsir-al-baghawi":  "ar-baghawi",
    "french-mokhtasar":      "fr-mokhtasar",
}

# Nombre de versets par sourate (1..114)
AYAH_COUNTS = [7,286,200,176,120,165,206,75,129,109,123,111,43,52,99,128,111,110,98,135,
112,78,118,72,77,227,93,88,69,60,34,30,73,54,45,83,182,88,75,85,54,53,89,59,37,35,38,29,
18,45,60,49,62,55,78,96,29,22,24,13,14,11,11,18,12,12,30,52,52,44,28,28,20,56,40,31,50,40,
46,42,29,19,36,25,22,17,19,26,30,20,15,21,11,8,8,19,5,8,8,11,11,8,3,9,5,4,7,3,6,3,5,4,5,6]

MIN_LEN = 5
WORKERS = 12


def fetch_ayah(slug, surah, ayah):
    url = f"{BASE}/{slug}/{surah}/{ayah}.json"
    for i in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=60) as r:
                obj = json.loads(r.read().decode("utf-8"))
                return (obj.get("text") or "").strip()
        except Exception:
            time.sleep(1 + i)
    return ""


def download_tafsir(slug, local_name):
    out_path = OUT_DIR / f"{local_name}.jsonl"
    if out_path.exists() and out_path.stat().st_size > 10000:
        print(f"  {local_name}: deja present, skip", flush=True)
        return 0

    tasks = [(s, a) for s in range(1, 115) for a in range(1, AYAH_COUNTS[s-1] + 1)]
    results = {}
    done = 0
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futs = {ex.submit(fetch_ayah, slug, s, a): (s, a) for s, a in tasks}
        for fut in as_completed(futs):
            s, a = futs[fut]
            txt = fut.result()
            if len(txt) >= MIN_LEN:
                results[(s, a)] = txt
            done += 1
            if done % 500 == 0:
                print(f"    {local_name}: {done}/{len(tasks)} ({len(results)} ok)", flush=True)

    n = 0
    with open(out_path, "w", encoding="utf-8") as f:
        for s in range(1, 115):
            for a in range(1, AYAH_COUNTS[s-1] + 1):
                if (s, a) in results:
                    f.write(json.dumps({"verse_key": f"{s}:{a}",
                                        "text": results[(s, a)]},
                                       ensure_ascii=False) + "\n")
                    n += 1
    print(f"  -> {out_path.name} ({n} versets)", flush=True)
    return n


def main():
    print(f"Tafsirs a telecharger: {list(TARGETS.values())}", flush=True)
    total = 0
    for slug, local in TARGETS.items():
        print(f"\n=== {slug} -> {local} ===", flush=True)
        try:
            total += download_tafsir(slug, local)
        except Exception as e:
            print(f"  ECHEC {slug}: {e}", flush=True)
    print(f"\nTOTAL versets tafsir: {total}", flush=True)
    print("TAFSIR DOWNLOAD DONE", flush=True)


if __name__ == "__main__":
    main()
