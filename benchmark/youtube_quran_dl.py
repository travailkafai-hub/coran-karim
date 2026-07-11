"""Download diverse Quran recitations from YouTube — audio only (m4a/opus), no ffmpeg.
Uses yt_dlp Python library with truststore SSL fix (proxy-compatible).
One search per surah. Only adds to manifest AFTER successful download.

Usage:
  python youtube_quran_dl.py [max_per_surah]   (default: 5)
"""
import truststore; truststore.inject_into_ssl()
import os, json, re, sys, time
import yt_dlp

ROOT     = os.path.dirname(os.path.abspath(__file__))
OUT_DIR  = os.path.join(ROOT, "data", "youtube_audio")
MANIFEST = os.path.join(ROOT, "data", "manifest_youtube.jsonl")
os.makedirs(OUT_DIR, exist_ok=True)

MAX_PER_SURAH  = int(sys.argv[1]) if len(sys.argv) > 1 else 5
MIN_DURATION_S = 5
MAX_DURATION_S = 18000  # 5h — pas d'exclusion reelle (recherche par nom de sourate);
                        # garde-fou contre une playlist "Coran complet" mal etiquetee

SURAHS = {
    1:"Al-Fatihah",   2:"Al-Baqarah",   3:"Ali-Imran",     4:"An-Nisa",
    5:"Al-Maidah",    6:"Al-Anam",      7:"Al-Araf",       8:"Al-Anfal",
    9:"At-Tawbah",    10:"Yunus",       11:"Hud",          12:"Yusuf",
    13:"Ar-Rad",      14:"Ibrahim",     15:"Al-Hijr",      16:"An-Nahl",
    17:"Al-Isra",     18:"Al-Kahf",     19:"Maryam",       20:"Ta-Ha",
    21:"Al-Anbiya",   22:"Al-Hajj",     23:"Al-Muminun",   24:"An-Nur",
    25:"Al-Furqan",   26:"Ash-Shuara",  27:"An-Naml",      28:"Al-Qasas",
    29:"Al-Ankabut",  30:"Ar-Rum",      31:"Luqman",       32:"As-Sajdah",
    33:"Al-Ahzab",    34:"Saba",        35:"Fatir",        36:"Ya-Sin",
    37:"As-Saffat",   38:"Sad",         39:"Az-Zumar",     40:"Ghafir",
    41:"Fussilat",    42:"Ash-Shura",   43:"Az-Zukhruf",   44:"Ad-Dukhan",
    45:"Al-Jathiyah", 46:"Al-Ahqaf",    47:"Muhammad",     48:"Al-Fath",
    49:"Al-Hujurat",  50:"Qaf",         51:"Adh-Dhariyat", 52:"At-Tur",
    53:"An-Najm",     54:"Al-Qamar",    55:"Ar-Rahman",    56:"Al-Waqiah",
    57:"Al-Hadid",    58:"Al-Mujadila", 59:"Al-Hashr",     60:"Al-Mumtahanah",
    61:"As-Saff",     62:"Al-Jumuah",   63:"Al-Munafiqun", 64:"At-Taghabun",
    65:"At-Talaq",    66:"At-Tahrim",   67:"Al-Mulk",      68:"Al-Qalam",
    69:"Al-Haqqah",   70:"Al-Maarij",   71:"Nuh",          72:"Al-Jinn",
    73:"Al-Muzzammil",74:"Al-Muddaththir",75:"Al-Qiyamah", 76:"Al-Insan",
    77:"Al-Mursalat",
    78:"An-Naba",    79:"An-Naziat",  80:"Abasa",       81:"At-Takwir",
    82:"Al-Infitar", 83:"Al-Mutaffifin",84:"Al-Inshiqaq",85:"Al-Buruj",
    86:"At-Tariq",   87:"Al-Ala",     88:"Al-Ghashiya", 89:"Al-Fajr",
    90:"Al-Balad",   91:"Ash-Shams",  92:"Al-Layl",     93:"Ad-Duha",
    94:"Ash-Sharh",  95:"At-Tin",     96:"Al-Alaq",     97:"Al-Qadr",
    98:"Al-Bayyina", 99:"Az-Zalzalah",100:"Al-Adiyat",  101:"Al-Qaria",
    102:"At-Takathur",103:"Al-Asr",   104:"Al-Humaza",  105:"Al-Fil",
    106:"Quraish",   107:"Al-Maun",   108:"Al-Kawthar", 109:"Al-Kafirun",
    110:"An-Nasr",   111:"Al-Masad",  112:"Al-Ikhlas",  113:"Al-Falaq",
    114:"An-Nas",
}

def search_videos(query: str, n: int) -> list[dict]:
    opts = {"quiet": True, "no_warnings": True, "extract_flat": True}
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(f"ytsearch{n}:{query}", download=False)
            results = []
            for e in (info.get("entries") or []):
                dur = e.get("duration") or 0
                if MIN_DURATION_S <= dur <= MAX_DURATION_S:
                    url = e.get("url") or e.get("webpage_url") or ""
                    if url:
                        results.append({"url": url, "title": e.get("title",""), "duration": dur})
            return results
    except Exception:
        return []

def download_audio(url: str, out_dir: str, vid_id: str) -> str | None:
    """Download best audio (m4a/opus) without ffmpeg. Returns file path or None."""
    tmpl = os.path.join(out_dir, f"{vid_id}.%(ext)s")
    opts = {
        "format": "bestaudio[ext=m4a]/bestaudio[ext=opus]/bestaudio",
        "outtmpl": tmpl,
        "quiet": True,
        "no_warnings": True,
        "no_playlist": True,
        "socket_timeout": 30,
        # No postprocessors — no ffmpeg needed
    }
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            ydl.download([url])
        # Find downloaded file
        for ext in ["m4a", "opus", "webm", "mp4", "ogg"]:
            p = os.path.join(out_dir, f"{vid_id}.{ext}")
            if os.path.exists(p) and os.path.getsize(p) > 5000:
                return p
    except Exception:
        pass
    return None

# Load already-done URLs from manifest
manifest_rows = []
already_done = set()
if os.path.exists(MANIFEST):
    for l in open(MANIFEST, encoding="utf-8"):
        obj = json.loads(l)
        url = obj.get("source_url", "")
        # Only mark as done if file actually exists
        fpath = os.path.join(ROOT, obj.get("audio", ""))
        if url and os.path.exists(fpath) and os.path.getsize(fpath) > 5000:
            already_done.add(url)
            manifest_rows.append(obj)

print(f"Starting — {len(SURAHS)} surahs × {MAX_PER_SURAH} videos max. "
      f"{len(already_done)} already downloaded.", flush=True)

total_new = 0
for surah_n, name in SURAHS.items():
    safe = re.sub(r'[^a-z0-9]', '_', name.lower())
    surah_dir = os.path.join(OUT_DIR, f"s{surah_n:03d}_{safe}")
    os.makedirs(surah_dir, exist_ok=True)

    found = sum(1 for r in manifest_rows if r.get("surah") == surah_n)
    if found >= MAX_PER_SURAH:
        print(f"S{surah_n} {name}: already {found}, skip", flush=True)
        continue

    print(f"S{surah_n} {name}:", flush=True)
    query = f"surah {name} full recitation quran"
    candidates = search_videos(query, n=MAX_PER_SURAH * 3)

    dl_count = 0
    for c in candidates:
        if dl_count + found >= MAX_PER_SURAH:
            break
        if c["url"] in already_done:
            continue
        vid_id = re.sub(r'[^a-zA-Z0-9_-]', '', c["url"].split("v=")[-1].split("&")[0])[:16]
        if not vid_id:
            vid_id = f"yt{int(time.time())}"
        print(f"  Downloading: {c['title'][:55]} ({c['duration']:.0f}s)", flush=True)
        fpath = download_audio(c["url"], surah_dir, vid_id)
        if fpath:
            row = {
                "surah": surah_n,
                "audio": os.path.relpath(fpath, ROOT).replace("\\", "/"),
                "ext": os.path.splitext(fpath)[1].lstrip("."),
                "duration_s": c["duration"],
                "title": c["title"],
                "source_url": c["url"],
                "aligned": False,
            }
            manifest_rows.append(row)
            already_done.add(c["url"])
            dl_count += 1
            total_new += 1
            print(f"  OK saved ({os.path.getsize(fpath)//1024}KB)", flush=True)
        else:
            print(f"  FAIL", flush=True)

    print(f"  S{surah_n}: +{dl_count} new", flush=True)

with open(MANIFEST, "w", encoding="utf-8") as f:
    for r in manifest_rows:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")

print(f"\nTotal new: {total_new}. manifest_youtube.jsonl: {len(manifest_rows)}", flush=True)
print("YOUTUBE DONE", flush=True)
