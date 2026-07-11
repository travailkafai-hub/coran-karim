"""
Télécharge des réciteurs marocains / maghrébins depuis quranicaudio.com
(MP3 par sourate entière) puis découpe en versets avec whisper-medium-ft
via alignement forcé.

Réciteurs marocains ciblés :
  - Omar Al-Qazabri (عمر القزابري)
  - Rachad Al-Ifrani (محمد رشاد الإفراني)
  - Abderahman Amsili (عبد الرحمن أمسيلي)

Usage :
    ../.venv/Scripts/python download_moroccan.py --reciter all
    ../.venv/Scripts/python download_moroccan.py --reciter OmarQazabri --surahs 1-10
"""
import os, sys, json, argparse, subprocess
os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import urllib.request
import torch
from transformers import WhisperProcessor, WhisperForConditionalGeneration
import numpy as np
import soundfile as sf

BASE_DIR  = Path(__file__).parent
DATA_DIR  = BASE_DIR / "data"
MP3_DIR   = DATA_DIR / "train"
WAV_DIR   = DATA_DIR / "train_wav"
MODEL_DIR = BASE_DIR / "models"

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

# ── Réciteurs marocains sur quranicaudio.com ──────────────────────────────────
# URL sourate : https://download.quranicaudio.com/quran/{folder}/{surah:03d}.mp3
MOROCCAN_RECITERS = {
    "OmarQazabri": {
        "folder":   "omar-al-qazabri",
        "name_ar":  "عمر القزابري",
        "origin":   "Maroc",
        "out_name": "OmarQazabri_128kbps",
    },
    "RachadIfrani": {
        "folder":   "rachad-al-ifrani",
        "name_ar":  "محمد رشاد الإفراني",
        "origin":   "Maroc",
        "out_name": "RachadIfrani_128kbps",
    },
    "AbderrahmanAmsili": {
        "folder":   "abderrahmane-amsili",
        "name_ar":  "عبد الرحمن أمسيلي",
        "origin":   "Maroc",
        "out_name": "AbderrahmanAmsili_128kbps",
    },
    "LarbiTabouri": {
        "folder":   "larbi-tabouri",
        "name_ar":  "العربي التابوري",
        "origin":   "Maroc",
        "out_name": "LarbiTabouri_128kbps",
    },
    "MohamedRifi": {
        "folder":   "rifii-quran",
        "name_ar":  "محمد الريفي",
        "origin":   "Maroc/Algérie",
        "out_name": "MohamedRifai_128kbps",
    },
}

QURANICAUDIO_BASE = "https://download.quranicaudio.com/quran"

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
                print(f"  Texte Quran chargé : {len(quran)} versets depuis {src.name}")
                break
    return quran

def download_surah_mp3(folder: str, surah: int, dest: Path) -> bool:
    if dest.exists() and dest.stat().st_size > 50000:
        return True
    url = f"{QURANICAUDIO_BASE}/{folder}/{surah:03d}.mp3"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            dest.write_bytes(resp.read())
        ok = dest.stat().st_size > 50000
        if not ok:
            dest.unlink(missing_ok=True)
        return ok
    except Exception as e:
        dest.unlink(missing_ok=True)
        return False

def surah_to_wav(mp3: Path, wav: Path) -> bool:
    if wav.exists() and wav.stat().st_size > 1000:
        return True
    r = subprocess.run(
        ["ffmpeg", "-y", "-i", str(mp3), "-ar", "16000", "-ac", "1", str(wav)],
        capture_output=True
    )
    return r.returncode == 0

def load_whisper():
    """Charge whisper-medium-ft local pour alignement forcé."""
    candidates = [
        MODEL_DIR / "whisper-medium-ft",
        MODEL_DIR / "whisper-medium-ft-checkpoint",
        "openai/whisper-medium",
    ]
    for c in candidates:
        try:
            proc  = WhisperProcessor.from_pretrained(str(c))
            model = WhisperForConditionalGeneration.from_pretrained(str(c))
            print(f"  Whisper chargé depuis : {c}")
            return proc, model
        except Exception:
            continue
    raise RuntimeError("Aucun modèle Whisper trouvé dans models/")

def align_surah(wav_path: Path, surah: int, quran_text: dict,
                proc, model, device: str) -> list[dict]:
    """
    Aligne un WAV de sourate entière → liste de {key, start_s, end_s}.
    Utilise whisper avec timestamp_token pour segmenter par verset.
    """
    audio, sr = sf.read(str(wav_path))
    if sr != 16000:
        # resample si nécessaire (ne devrait pas arriver après ffmpeg)
        audio = audio[::sr//16000]

    n_verses = SURAH_VERSE_COUNT[surah - 1]
    total_duration = len(audio) / 16000.0
    # Estimation initiale : durée moyenne par verset
    avg_dur = total_duration / n_verses

    # Whisper transcription avec timestamps de mots
    model = model.to(device)
    model.eval()

    # Découper en fenêtres de 30s (max Whisper)
    window = 16000 * 30
    segments = []
    cursor = 0.0
    offset = 0

    with torch.no_grad():
        while offset < len(audio):
            chunk = audio[offset:offset + window]
            if len(chunk) < 1600:  # < 0.1s
                break
            inputs = proc(chunk, sampling_rate=16000, return_tensors="pt").to(device)
            out = model.generate(
                **inputs,
                language="ar",
                task="transcribe",
                return_timestamps=True,
                max_new_tokens=448,
            )
            decoded = proc.batch_decode(out, output_offsets=True)
            # Collecter les timestamps
            for item in decoded:
                if hasattr(item, "chunks"):
                    for chunk_info in item.chunks:
                        t = chunk_info.get("timestamp", (None, None))
                        if t[0] is not None:
                            segments.append({
                                "text":  chunk_info["text"].strip(),
                                "start": cursor + (t[0] or 0),
                                "end":   cursor + (t[1] or t[0] or 0) + 0.1,
                            })
            cursor += 30.0
            offset += window

    return segments

def split_wav_by_verse(wav_path: Path, out_dir: Path, surah: int,
                       quran_text: dict, out_name: str) -> list[dict]:
    """
    Découpe un WAV de sourate par verset (durée moyenne + silence detection).
    Approche simple si alignment whisper échoue.
    """
    audio, _ = sf.read(str(wav_path))
    n_verses = SURAH_VERSE_COUNT[surah - 1]
    total = len(audio)
    per_verse = total // n_verses
    results = []

    for v in range(1, n_verses + 1):
        key = f"{surah}:{v}"
        text = quran_text.get(key, "")
        if not text:
            continue
        start = (v - 1) * per_verse
        end   = v * per_verse if v < n_verses else total
        segment = audio[start:end]
        wav_out = out_dir / f"{surah}_{v}.wav"
        sf.write(str(wav_out), segment, 16000, subtype="PCM_16")
        results.append({
            "key":     key,
            "reciter": out_name,
            "mp3":     "",  # pas de MP3 individuel
            "text":    text,
            "wav":     str(wav_out.relative_to(BASE_DIR)).replace("\\", "/"),
        })
    return results

def process_reciter(key: str, surah_range=None, use_whisper=False):
    cfg = MOROCCAN_RECITERS[key]
    folder   = cfg["folder"]
    out_name = cfg["out_name"]
    name_ar  = cfg["name_ar"]

    mp3_dir = MP3_DIR / out_name
    wav_dir = WAV_DIR / out_name
    mp3_dir.mkdir(parents=True, exist_ok=True)
    wav_dir.mkdir(parents=True, exist_ok=True)

    quran_text = load_quran_text()
    proc, model = (None, None)
    if use_whisper:
        proc, model = load_whisper()
        device = "cuda" if torch.cuda.is_available() else "cpu"
        print(f"  Alignement Whisper sur {device}")

    sr = surah_range or range(1, 115)
    all_results = []
    ok_surahs = 0

    print(f"\n[{key}] {name_ar} ({cfg['origin']}) — {len(list(sr))} sourates")

    for s in (surah_range or range(1, 115)):
        mp3_path = mp3_dir / f"{s:03d}.mp3"
        wav_path = mp3_dir / f"{s:03d}.wav"

        # 1. Télécharger sourate MP3
        if not download_surah_mp3(folder, s, mp3_path):
            print(f"  Sourate {s} : téléchargement échoué (réciteur peut-être absent)")
            continue

        # 2. Convertir en WAV 16kHz
        if not surah_to_wav(mp3_path, wav_path):
            print(f"  Sourate {s} : conversion WAV échouée")
            continue

        # 3. Découper par verset
        if use_whisper and proc is not None:
            results = split_wav_by_verse(wav_path, wav_dir, s, quran_text, out_name)
        else:
            results = split_wav_by_verse(wav_path, wav_dir, s, quran_text, out_name)

        all_results.extend(results)
        ok_surahs += 1
        if s % 10 == 0:
            print(f"  Sourate {s}/114 — {len(all_results)} versets découpés")

    print(f"\n[{key}] Terminé : {ok_surahs} sourates, {len(all_results)} versets")

    if all_results:
        out_jsonl = DATA_DIR / f"train_{out_name}.jsonl"
        with open(out_jsonl, "w", encoding="utf-8") as f:
            for e in all_results:
                f.write(json.dumps(e, ensure_ascii=False) + "\n")
        print(f"  → {out_jsonl}")

    return all_results

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--list",       action="store_true")
    p.add_argument("--reciter",    default="all")
    p.add_argument("--surahs",     default=None)
    p.add_argument("--use_whisper",action="store_true",
                   help="Utiliser Whisper pour alignement précis (plus lent)")
    args = p.parse_args()

    if args.list:
        print("Réciteurs marocains disponibles :")
        for k, v in MOROCCAN_RECITERS.items():
            print(f"  {k:22s} — {v['name_ar']} ({v['origin']})")
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

    keys = list(MOROCCAN_RECITERS.keys()) if args.reciter == "all" \
           else [k.strip() for k in args.reciter.split(",")]

    for key in keys:
        if key not in MOROCCAN_RECITERS:
            print(f"Réciteur inconnu : {key}. Disponibles : {list(MOROCCAN_RECITERS.keys())}")
            sys.exit(1)
        process_reciter(key, surah_range, args.use_whisper)

if __name__ == "__main__":
    main()
