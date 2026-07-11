"""
Télécharge des réciteurs depuis YouTube (yt-dlp) et aligne les versets
avec whisper-medium-ft en alignement forcé.

Usage :
    # Télécharger depuis une playlist YouTube :
    ../.venv/Scripts/python download_youtube_reciters.py \
        --reciter OmarQazabri \
        --url "https://www.youtube.com/playlist?list=PLxxxxxxx" \
        --surahs 1-114

    # Mode verset-par-verset (si playlist organisée par sourate) :
    ../.venv/Scripts/python download_youtube_reciters.py \
        --reciter OmarQazabri \
        --surah_urls surah_urls_qazabri.txt

    # Lister les réciteurs préconfigurés :
    ../.venv/Scripts/python download_youtube_reciters.py --list
"""
import os, sys, json, argparse, subprocess, re
os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

from pathlib import Path
import soundfile as sf
import numpy as np
import torch

BASE_DIR = Path(__file__).parent
DATA_DIR = BASE_DIR / "data"
WAV_DIR  = DATA_DIR / "train_wav"
MP3_DIR  = DATA_DIR / "train"
YTDLP    = "yt-dlp"

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

# ── Réciteurs marocains préconfigurés ────────────────────────────────────────
# Ajoute les URLs de tes playlists YouTube ici.
# Format : { "id": { "name_ar", "out_name", "playlist_url" ou "surah_urls" } }
MOROCCAN_PRESETS = {
    "OmarQazabri": {
        "name_ar":  "عمر القزابري",
        "out_name": "OmarQazabri_128kbps",
        # URL à remplir — cherche "عمر القزابري القرآن الكريم" sur YouTube
        "playlist_url": "",
        # Ou liste de URLs par sourate (fichier texte, une URL par ligne)
        "surah_urls_file": "urls_qazabri.txt",
    },
    "RachadIfrani": {
        "name_ar":  "محمد رشاد الإفراني",
        "out_name": "RachadIfrani_128kbps",
        "playlist_url": "",
        "surah_urls_file": "urls_ifrani.txt",
    },
    "AbderrahmanAmsili": {
        "name_ar":  "عبد الرحمن أمسيلي",
        "out_name": "AbderrahmanAmsili_128kbps",
        "playlist_url": "",
        "surah_urls_file": "urls_amsili.txt",
    },
    "LarbiTabouri": {
        "name_ar":  "العربي التابوري",
        "out_name": "LarbiTabouri_128kbps",
        "playlist_url": "",
        "surah_urls_file": "urls_tabouri.txt",
    },
    "MohamedRifi": {
        "name_ar":  "محمد الريفي",
        "out_name": "MohamedRifi_128kbps",
        "playlist_url": "",
        "surah_urls_file": "urls_rifi.txt",
    },
    "NouvelReciteur": {
        "name_ar":  "— à définir —",
        "out_name": "custom_reciter",
        "playlist_url": "",
        "surah_urls_file": "urls_custom.txt",
    },
}

def list_presets():
    print("Réciteurs marocains préconfigurés :")
    print("(Remplis les URLs YouTube dans le script ou via --url)\n")
    for k, v in MOROCCAN_PRESETS.items():
        url = v.get("playlist_url", "") or f"→ fichier {v.get('surah_urls_file','')}"
        print(f"  {k:22s}  {v['name_ar']:30s}  {url}")
    print()
    print("Pour télécharger, tu as besoin de l'URL YouTube.")
    print("Recherche sur YouTube : عمر القزابري القرآن كاملا")
    print("Ensuite : --reciter OmarQazabri --url 'https://youtube.com/...'")

YTDLP_FLAGS = ["--no-check-certificate", "--no-warnings"]

def download_audio_ytdlp(url: str, out_path: Path) -> bool:
    """Télécharge audio MP3 via yt-dlp."""
    if out_path.exists() and out_path.stat().st_size > 100000:
        return True
    cmd = [YTDLP, "-x", "--audio-format", "mp3", "--audio-quality", "0",
           "-o", str(out_path), "--no-playlist", "--quiet"] + YTDLP_FLAGS + [url]
    r = subprocess.run(cmd, capture_output=True, timeout=600)
    return out_path.exists() and out_path.stat().st_size > 10000

def download_playlist_ytdlp(playlist_url: str, out_dir: Path) -> list[Path]:
    """Télécharge toutes les vidéos d'une playlist (index = numéro sourate)."""
    out_dir.mkdir(parents=True, exist_ok=True)
    # %(playlist_index)s est le numéro de la vidéo dans la playlist = numéro sourate
    template = str(out_dir / "%(playlist_index)03d.%(ext)s")
    cmd = [YTDLP, "-x", "--audio-format", "mp3", "--audio-quality", "0",
           "-o", template, "--yes-playlist", "--progress",
           "--concurrent-fragments", "4"] + YTDLP_FLAGS + [playlist_url]
    print(f"  Téléchargement playlist → {out_dir}")
    r = subprocess.run(cmd, capture_output=False, timeout=72000)
    return sorted(out_dir.glob("*.mp3"))

def to_wav_16k(mp3: Path, wav: Path) -> bool:
    if wav.exists() and wav.stat().st_size > 1000:
        return True
    r = subprocess.run(
        ["ffmpeg", "-y", "-i", str(mp3), "-ar", "16000", "-ac", "1", str(wav)],
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
                        if e.get("text"):
                            quran[e["key"]] = e["text"]
                    except Exception:
                        pass
            if quran:
                print(f"  Texte chargé : {len(quran)} versets")
                break
    return quran

def detect_surah_from_title(title: str) -> int | None:
    """Essaie de détecter le numéro de sourate dans le titre YouTube."""
    # Patterns courants : "سورة يس 36", "Sourate 36 Ya-Sin", "036 Ya-Sin"
    m = re.search(r'(?:سورة|surate?|sourate?)[^\d]*(\d+)', title, re.IGNORECASE)
    if m:
        return int(m.group(1))
    m = re.search(r'\b(\d{1,3})\b', title)
    if m:
        n = int(m.group(1))
        if 1 <= n <= 114:
            return n
    return None

def split_by_verse_uniform(audio: np.ndarray, surah: int, out_dir: Path,
                            out_name: str, quran_text: dict) -> list[dict]:
    """Découpe uniforme : durée totale / nb versets."""
    n_verses = SURAH_VERSE_COUNT[surah - 1]
    total = len(audio)
    per_v = total // n_verses
    results = []
    for v in range(1, n_verses + 1):
        key  = f"{surah}:{v}"
        text = quran_text.get(key, "")
        if not text:
            continue
        s = (v - 1) * per_v
        e = v * per_v if v < n_verses else total
        seg = audio[s:e]
        wav_out = out_dir / f"{surah}_{v}.wav"
        sf.write(str(wav_out), seg, 16000, subtype="PCM_16")
        results.append({
            "key":     key,
            "reciter": out_name,
            "mp3":     "",
            "text":    text,
            "wav":     str(wav_out.relative_to(BASE_DIR)).replace("\\", "/"),
        })
    return results

def process_url(url: str, surah: int, out_name: str,
                mp3_dir: Path, wav_dir: Path, quran_text: dict) -> list[dict]:
    mp3_path = mp3_dir / f"{surah:03d}.mp3"
    wav_path = mp3_dir / f"{surah:03d}.wav"

    if not download_audio_ytdlp(url, mp3_path):
        print(f"  Sourate {surah} : échec téléchargement")
        return []
    if not to_wav_16k(mp3_path, wav_path):
        print(f"  Sourate {surah} : échec conversion WAV")
        return []

    audio, _ = sf.read(str(wav_path))
    results = split_by_verse_uniform(audio, surah, wav_dir, out_name, quran_text)
    print(f"  Sourate {surah} : {len(results)} versets découpés ({len(audio)/16000:.0f}s)")
    return results

def process_reciter(key: str, url: str = "", surah_range=None):
    cfg = MOROCCAN_PRESETS.get(key)
    if cfg is None:
        # Reciteur personnalisé via --reciter custom --url URL --name NOM
        print(f"Clé inconnue : {key}")
        return

    out_name = cfg["out_name"]
    mp3_dir  = MP3_DIR / out_name
    wav_dir  = WAV_DIR / out_name
    mp3_dir.mkdir(parents=True, exist_ok=True)
    wav_dir.mkdir(parents=True, exist_ok=True)

    quran_text = load_quran_text()
    playlist_url = url or cfg.get("playlist_url", "")
    urls_file    = BASE_DIR / cfg.get("surah_urls_file", "")

    all_results = []

    # Cas 1 : playlist YouTube (une vidéo par sourate)
    if playlist_url:
        mp3_files = download_playlist_ytdlp(playlist_url, mp3_dir / "raw")
        print(f"  {len(mp3_files)} fichiers téléchargés")
        for mp3 in sorted(mp3_files):
            surah = detect_surah_from_title(mp3.stem) or 0
            if surah < 1 or surah > 114:
                print(f"  Sourate inconnue pour : {mp3.name}")
                continue
            wav_p = mp3_dir / f"{surah:03d}.wav"
            if to_wav_16k(mp3, wav_p):
                audio, _ = sf.read(str(wav_p))
                res = split_by_verse_uniform(audio, surah, wav_dir, out_name, quran_text)
                all_results.extend(res)

    # Cas 2 : fichier de URLs (une URL par ligne = une sourate)
    elif urls_file.exists():
        with open(urls_file) as f:
            lines = [l.strip() for l in f if l.strip() and not l.startswith("#")]
        print(f"  {len(lines)} URLs chargées depuis {urls_file.name}")
        surahs = surah_range or range(1, len(lines) + 1)
        for i, (s, line_url) in enumerate(zip(surahs, lines)):
            parts = line_url.split()
            video_url = parts[0]
            res = process_url(video_url, s, out_name, mp3_dir, wav_dir, quran_text)
            all_results.extend(res)

    else:
        print(f"\nAucune URL fournie pour {key}.")
        print(f"Options :")
        print(f"  1. --url 'YOUTUBE_PLAYLIST_URL'")
        print(f"  2. Créer le fichier {urls_file.name} avec une URL par ligne")
        print(f"\nRecherche YouTube suggérée : {cfg['name_ar']} القرآن الكريم كاملا\n")
        return

    if all_results:
        out_jsonl = DATA_DIR / f"train_{out_name}.jsonl"
        with open(out_jsonl, "w", encoding="utf-8") as f:
            for e in all_results:
                f.write(json.dumps(e, ensure_ascii=False) + "\n")
        print(f"\n[{key}] {len(all_results)} versets → {out_jsonl}")

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--list",    action="store_true")
    p.add_argument("--reciter", default=None,  help="ID du réciteur (voir --list)")
    p.add_argument("--url",     default="",    help="URL YouTube (playlist ou vidéo)")
    p.add_argument("--surahs",  default=None,  help="Sourates ex: 1-10 ou 36,112")
    p.add_argument("--out_name",default=None,  help="Nom dossier sortie (si réciteur personnalisé)")
    args = p.parse_args()

    if args.list:
        list_presets()
        return

    if not args.reciter:
        p.print_help()
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

    if args.reciter not in MOROCCAN_PRESETS and args.out_name:
        MOROCCAN_PRESETS[args.reciter] = {
            "name_ar":  args.reciter,
            "out_name": args.out_name,
            "playlist_url": args.url,
            "surah_urls_file": "",
        }

    process_reciter(args.reciter, url=args.url, surah_range=surah_range)

if __name__ == "__main__":
    main()
