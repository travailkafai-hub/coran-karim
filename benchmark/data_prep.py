"""Prepare benchmark dataset: Quran recitation audio (everyayah) + verified reference text (quran.com API).
Builds correct + corrupted-reference cases for mistake-detection evaluation.
"""
import truststore; truststore.inject_into_ssl()
import os, json, io, requests, subprocess, random
import soundfile as sf
import numpy as np

random.seed(0)
ROOT = os.path.dirname(os.path.abspath(__file__))
AUDIO_DIR = os.path.join(ROOT, "data", "audio")
os.makedirs(AUDIO_DIR, exist_ok=True)

# Short ayahs (well under 30s). (surah, ayah)
AYAHS = [
    (112,1),(112,2),(112,3),(112,4),   # Al-Ikhlas
    (108,1),(108,2),(108,3),           # Al-Kawthar
    (110,1),(110,2),(110,3),           # An-Nasr
    (111,1),(111,2),(111,3),           # Al-Masad
    (36,1),(36,2),(36,3),              # Ya-Sin opening
]
RECITER = "Alafasy_128kbps"
EVERYAYAH = "https://everyayah.com/data/{rec}/{s:03d}{a:03d}.mp3"
QURAN_API = "https://api.quran.com/api/v4/verses/by_key/{s}:{a}?fields=text_uthmani,text_imlaei"

FFMPEG = os.environ.get("FFMPEG_BIN", "ffmpeg")

def load_mp3_as_16k_wav(mp3_bytes, out_wav):
    """Decode mp3 -> mono 16kHz wav via ffmpeg."""
    p = subprocess.run(
        [FFMPEG,"-hide_banner","-loglevel","error","-i","pipe:0",
         "-ac","1","-ar","16000","-f","wav","pipe:1"],
        input=mp3_bytes, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.decode()[:200])
    with open(out_wav,"wb") as f:
        f.write(p.stdout)
    data, sr = sf.read(out_wav)
    return len(data)/sr

def corrupt(words):
    """Return (corrupted_text, description) deliberately introducing one error."""
    w = words.copy()
    if len(w) < 2:
        return None
    mode = random.choice(["delete","substitute","swap"])
    i = random.randrange(len(w))
    if mode == "delete":
        removed = w.pop(i); desc = f"mot supprime: '{removed}' (pos {i})"
    elif mode == "substitute":
        orig = w[i]; w[i] = "اللَّهِ" if orig != "اللَّهِ" else "رَبِّ"; desc=f"substitution pos {i}: '{orig}'->'{w[i]}'"
    else:
        j = (i+1) % len(w)
        w[i],w[j]=w[j],w[i]; desc=f"inversion pos {i}<->{j}"
    return " ".join(w), desc

dataset = []
for (s,a) in AYAHS:
    key=f"{s}:{a}"
    # text
    r = requests.get(QURAN_API.format(s=s,a=a), timeout=20); r.raise_for_status()
    v = r.json()["verse"]
    uthmani = v["text_uthmani"]
    # audio
    wav = os.path.join(AUDIO_DIR, f"{s:03d}{a:03d}.wav")
    if not os.path.exists(wav):
        mp = requests.get(EVERYAYAH.format(rec=RECITER,s=s,a=a), timeout=30); mp.raise_for_status()
        dur = load_mp3_as_16k_wav(mp.content, wav)
    else:
        d,sr=sf.read(wav); dur=len(d)/sr
    corr = corrupt(uthmani.split())
    dataset.append({
        "key": key, "surah": s, "ayah": a,
        "wav": os.path.relpath(wav, ROOT).replace("\\","/"),
        "duration_s": round(dur,2),
        "ref_uthmani": uthmani,
        "ref_imlaei": v.get("text_imlaei",""),
        "corrupt_ref": corr[0] if corr else uthmani,
        "corrupt_desc": corr[1] if corr else "n/a",
    })
    print(f"{key:8s} {dur:5.1f}s  {uthmani}")

with open(os.path.join(ROOT,"data","dataset.json"),"w",encoding="utf-8") as f:
    json.dump(dataset,f,ensure_ascii=False,indent=2)
print(f"\nSaved {len(dataset)} samples -> data/dataset.json")
