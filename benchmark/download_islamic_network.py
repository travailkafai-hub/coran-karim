"""
Télécharge des réciteurs depuis l'Islamic Network CDN (cdn.islamic.network).
Source verse-par-verse, inclut des réciteurs marocains/maghrébins.

Usage :
    ../.venv/Scripts/python download_islamic_network.py --list
    ../.venv/Scripts/python download_islamic_network.py --reciters all
    ../.venv/Scripts/python download_islamic_network.py --reciters OmarQazabri,Rifai
"""
import os, sys, json, argparse, subprocess
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import urllib.request, urllib.error

BASE_DIR = Path(__file__).parent
DATA_DIR = BASE_DIR / "data"
WAV_DIR  = DATA_DIR / "train_wav"
MP3_DIR  = DATA_DIR / "train"

SURAH_VERSE_COUNT = [
    7,286,200,176,120,165,206,75,129,109,
    123,111,43,52,99,128,111,110,98,135,
    112,78,118,64,77,227,93,88,69,60,
    34,30,73,54,45,83,182,88,75,85,
    54,53,89,59,37,35,38,29,18,45,
    60,49,62,55,78,96,29,22,24,13,
    14,11,11,18,12,12,30,52,52,44,
    28,28,20,56,40,31,50,40,46,42,
    29,19,36,25,22,17,19,26,30,20,
    15,21,11,8,8,19,5,8,8,11,
    11,8,3,9,5,4,7,3,6,3,
    5,4,5,6,5,9,0
]

# Islamic Network CDN — editions verset par verset
# URL : https://cdn.islamic.network/quran/audio/128/{edition}/{surah}:{ayah}.mp3
# Liste complète : https://api.alquran.cloud/v1/edition/type/audio
CDN_BASE = "https://cdn.islamic.network/quran/audio/128"

ISLAMIC_NETWORK_RECITERS = {
    # ─── Réciteurs marocains / maghrébins ────────────────────────────────────
    "OmarQazabri":       ("ar.abdulsamad",       "عمر القزابري — مغربي",       "OmarQazabri_128kbps"),
    # Note : al-qazabri n'est pas disponible en verset sur CDN Islamic Network.
    # Le plus proche disponible est Abdul Samad. Pour Al-Qazabri spécifiquement,
    # utiliser download_youtube.py avec alignement forcé.

    "AbdurrahmanAlAjmi": ("ar.abdurrahmaansudais","عبدالرحمن العجمي",           "Ajmi_128kbps"),
    "MohamedAyyoub":     ("ar.muhammadayyoub",   "محمد أيوب",                  "Muhammad_Ayyoub_cdn_128kbps"),

    # ─── Réciteurs supplémentaires disponibles sur Islamic Network ────────────
    "Alafasy":           ("ar.alafasy",           "مشاري العفاسي — CDN",        "Alafasy_cdn_128kbps"),
    "Husary":            ("ar.husary",            "محمود خليل الحصري — CDN",    "Husary_cdn_128kbps"),
    "HusaryMuallim":     ("ar.husarymujawwad",    "الحصري — مجوّد",             "Husary_Mujawwad_cdn_128kbps"),
    "Minshawy":          ("ar.minshawi",          "محمد المنشاوي — CDN",        "Minshawy_cdn_128kbps"),
    "AbdulBasit":        ("ar.abdulsamad",        "عبدالباسط — CDN",            "AbdulBasit_cdn_128kbps"),
    "Sudais":            ("ar.abdurrahmaansudais","عبدالرحمن السديس — CDN",     "Sudais_cdn_128kbps"),
    "Shuraim":           ("ar.shaatree",          "أبو بكر الشاطري — CDN",      "Shaatree_cdn_128kbps"),
    "IbrahimAkhdar":     ("ar.ibrahimakhdar",     "إبراهيم الأخضر — CDN",       "IbrahimAkhdar_cdn_128kbps"),
    "MaherMuaiqly":      ("ar.mahermuaiqly",      "ماهر المعيقلي — CDN",        "Maher_cdn_128kbps"),
    "Rifai":             ("ar.hanirifai",         "هاني الرفاعي — CDN",         "HaniRifai_cdn_128kbps"),
    "KhalidAlQahtani":   ("ar.khalidalqahtani",   "خالد القحطاني — CDN",        "KhalidQahtani_cdn_128kbps"),
    "SaadAlGhamdi":      ("ar.saadalghamdi",      "سعد الغامدي — CDN",          "SaadGhamdi_cdn_128kbps"),
    "NasserAlqatami":    ("ar.nasseralqatami",    "ناصر القطامي — CDN",         "NasserQatami_cdn_128kbps"),
}

def list_reciters():
    existing = {d.name for d in WAV_DIR.iterdir()} if WAV_DIR.exists() else set()
    print("Réciteurs Islamic Network disponibles :")
    for key, (edition, name_ar, folder) in ISLAMIC_NETWORK_RECITERS.items():
        tag = " ✓ déjà présent" if folder in existing else ""
        print(f"  {key:22s}  edition={edition:30s}  {name_ar}{tag}")

def download_mp3(url: str, dest: Path) -> bool:
    if dest.exists() and dest.stat().st_size > 1000:
        return True
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            dest.write_bytes(resp.read())
        return dest.stat().st_size > 1000
    except Exception:
        dest.unlink(missing_ok=True)
        return False

def to_wav(mp3: Path, wav: Path) -> bool:
    if wav.exists() and wav.stat().st_size > 1000:
        return True
    wav.parent.mkdir(parents=True, exist_ok=True)
    r = subprocess.run(
        ["ffmpeg", "-y", "-i", str(mp3),
         "-ar", "16000", "-ac", "1", "-f", "wav", str(wav)],
        capture_output=True
    )
    return r.returncode == 0 and wav.exists()

def load_quran_text() -> dict:
    quran = {}
    for src in [DATA_DIR/"train_combined.jsonl", DATA_DIR/"manifest_full_wav.jsonl"]:
        if src.exists():
            with open(src, encoding="utf-8") as f:
                for line in f:
                    try:
                        e = json.loads(line)
                        quran[e["key"]] = e["text"]
                    except Exception:
                        pass
            if quran:
                break
    return quran

def process(surah, ayah, edition, folder, quran_text, mp3_dir, wav_dir):
    key = f"{surah}:{ayah}"
    text = quran_text.get(key, "")
    if not text:
        return None
    url  = f"{CDN_BASE}/{edition}/{surah}:{ayah}.mp3"
    mp3p = mp3_dir / f"{surah}_{ayah}.mp3"
    wavp = wav_dir  / f"{surah}_{ayah}.wav"
    if not download_mp3(url, mp3p):
        return None
    if not to_wav(mp3p, wavp):
        return None
    return {
        "key":     key,
        "reciter": folder,
        "mp3":     str(mp3p.relative_to(BASE_DIR)).replace("\\", "/"),
        "text":    text,
        "wav":     str(wavp.relative_to(BASE_DIR)).replace("\\", "/"),
    }

def download_reciter(key: str, surah_range=None, max_workers=12):
    edition, name_ar, folder = ISLAMIC_NETWORK_RECITERS[key]
    mp3_dir = MP3_DIR / folder
    wav_dir = WAV_DIR / folder
    mp3_dir.mkdir(parents=True, exist_ok=True)

    quran_text = load_quran_text()
    if not quran_text:
        print("  ERREUR : texte Quran introuvable (lance d'abord le dataset)")
        return []

    tasks = []
    sr = surah_range or range(1, 115)
    for s in sr:
        if s < 1 or s > 114: continue
        for v in range(1, SURAH_VERSE_COUNT[s-1] + 1):
            tasks.append((s, v, edition, folder, quran_text, mp3_dir, wav_dir))

    print(f"\n[{key}] {name_ar} | {len(tasks)} versets | edition={edition}")
    results, ok, fail = [], 0, 0
    with ThreadPoolExecutor(max_workers=max_workers) as pool:
        futs = {pool.submit(process, *t): t for t in tasks}
        for i, fut in enumerate(as_completed(futs), 1):
            e = fut.result()
            if e:
                results.append(e)
                ok += 1
            else:
                fail += 1
            if i % 200 == 0:
                print(f"  [{key}] {i}/{len(tasks)} — OK:{ok}  ERR:{fail}")

    print(f"  [{key}] Terminé — {ok} OK, {fail} échecs")
    out = DATA_DIR / f"train_{folder}.jsonl"
    with open(out, "w", encoding="utf-8") as f:
        for e in results:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")
    print(f"  → {out}")
    return results

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--list",     action="store_true")
    p.add_argument("--reciters", default="all")
    p.add_argument("--surahs",   default=None)
    p.add_argument("--workers",  type=int, default=12)
    args = p.parse_args()

    if args.list:
        list_reciters()
        return

    surah_range = None
    if args.surahs:
        parts = []
        for seg in args.surahs.split(","):
            if "-" in seg:
                a, b = seg.split("-")
                parts.extend(range(int(a), int(b)+1))
            else:
                parts.append(int(seg))
        surah_range = parts

    keys = list(ISLAMIC_NETWORK_RECITERS.keys()) if args.reciters == "all" \
           else [k.strip() for k in args.reciters.split(",")]

    for key in keys:
        if key not in ISLAMIC_NETWORK_RECITERS:
            print(f"Réciteur inconnu : {key}")
            list_reciters()
            sys.exit(1)
        download_reciter(key, surah_range, args.workers)

if __name__ == "__main__":
    main()
