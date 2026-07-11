"""Convert manifest_full.jsonl (255k mp3) -> 16kHz mono wav. Resumable. Writes manifest_full_wav.jsonl."""
import os, json, subprocess, time
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.abspath(__file__))
FF = os.environ.get("FFMPEG_BIN",
    r"C:\Users\Adam\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-8.1.1-full_build\bin\ffmpeg.exe")
if not os.path.exists(FF):
    FF = "ffmpeg"

MANIFEST_IN  = os.path.join(ROOT, "data", "manifest_full.jsonl")
MANIFEST_OUT = os.path.join(ROOT, "data", "manifest_full_wav.jsonl")
WORKERS = 32

rows = [json.loads(l) for l in open(MANIFEST_IN, encoding="utf-8")]
print(f"Total clips in manifest: {len(rows)}", flush=True)

# Count already-done to give a useful start estimate
wav_out_dir = os.path.join(ROOT, "data", "train_wav")
existing = sum(
    1 for r in rows
    for dst in [os.path.join(ROOT,
        r["mp3"].replace("data/train/", "data/train_wav/").rsplit(".", 1)[0] + ".wav")]
    if os.path.exists(dst) and os.path.getsize(dst) > 1000
)
print(f"Already converted: {existing} / {len(rows)}", flush=True)

def conv(r):
    src = os.path.join(ROOT, r["mp3"].replace("/", os.sep))
    dst = os.path.join(ROOT,
        r["mp3"].replace("data/train/", "data/train_wav/").replace("/", os.sep)
        .rsplit(".", 1)[0] + ".wav")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.exists(dst) and os.path.getsize(dst) > 1000:
        r2 = dict(r)
        r2["wav"] = os.path.relpath(dst, ROOT).replace("\\", "/")
        return r2, "skip"
    if not os.path.exists(src) or os.path.getsize(src) < 500:
        return None, "missing"
    p = subprocess.run(
        [FF, "-hide_banner", "-loglevel", "error", "-y", "-i", src,
         "-ac", "1", "-ar", "16000", dst],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if p.returncode != 0 or not os.path.exists(dst) or os.path.getsize(dst) < 500:
        return None, "fail"
    r2 = dict(r)
    r2["wav"] = os.path.relpath(dst, ROOT).replace("\\", "/")
    return r2, "ok"

out = []; done = skip = fail = missing = 0
t0 = time.time()

with ThreadPoolExecutor(max_workers=WORKERS) as ex:
    futs = [ex.submit(conv, r) for r in rows]
    for i, f in enumerate(as_completed(futs)):
        r2, status = f.result()
        if status == "ok":    done += 1;    out.append(r2)
        elif status == "skip": skip += 1;   out.append(r2)
        elif status == "fail": fail += 1
        elif status == "missing": missing += 1
        if (i + 1) % 5000 == 0:
            elapsed = time.time() - t0
            rate = (i + 1) / elapsed
            eta = (len(rows) - i - 1) / rate / 60
            print(f"  {i+1}/{len(rows)}  new={done} skip={skip} fail={fail} missing={missing}  "
                  f"rate={rate:.0f}/s  ETA={eta:.0f}min", flush=True)

with open(MANIFEST_OUT, "w", encoding="utf-8") as f:
    for r in out:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")

elapsed = (time.time() - t0) / 60
print(f"\nConverted: {done} new, {skip} skip, {fail} fail, {missing} missing — {elapsed:.1f}min", flush=True)
print(f"manifest_full_wav.jsonl: {len(out)} clips", flush=True)
print("CONVERT FULL DONE", flush=True)
