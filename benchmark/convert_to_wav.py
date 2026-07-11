"""Robustly convert all dataset mp3 -> 16kHz mono wav via ffmpeg; rewrite manifest_wav.jsonl."""
import os, json, subprocess, glob
from concurrent.futures import ThreadPoolExecutor, as_completed
ROOT=os.path.dirname(os.path.abspath(__file__))
FF=os.environ.get("FFMPEG_BIN", r"C:\Users\Adam\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-8.1.1-full_build\bin\ffmpeg.exe")
if not os.path.exists(FF): FF="ffmpeg"

rows=[json.loads(l) for l in open(os.path.join(ROOT,"data","manifest.jsonl"),encoding="utf-8")]

def conv(r):
    src=os.path.join(ROOT,r["mp3"])
    dst=src.replace(os.sep+"train"+os.sep, os.sep+"train_wav"+os.sep).rsplit(".",1)[0]+".wav"
    os.makedirs(os.path.dirname(dst),exist_ok=True)
    if not (os.path.exists(dst) and os.path.getsize(dst)>1000):
        p=subprocess.run([FF,"-hide_banner","-loglevel","error","-y","-i",src,"-ac","1","-ar","16000",dst],
                         stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        if p.returncode!=0 or not os.path.exists(dst): return None
    r2=dict(r); r2["wav"]=os.path.relpath(dst,ROOT).replace("\\","/"); return r2

out=[]; fail=0
with ThreadPoolExecutor(max_workers=16) as ex:
    for i,f in enumerate(as_completed([ex.submit(conv,r) for r in rows])):
        r2=f.result()
        if r2: out.append(r2)
        else: fail+=1
        if (i+1)%2000==0: print(f"{i+1}/{len(rows)} (fail={fail})",flush=True)
with open(os.path.join(ROOT,"data","manifest_wav.jsonl"),"w",encoding="utf-8") as f:
    for r in out: f.write(json.dumps(r,ensure_ascii=False)+"\n")
print(f"Converted {len(out)} (fail {fail}) -> manifest_wav.jsonl",flush=True)
print("CONVERT DONE",flush=True)
