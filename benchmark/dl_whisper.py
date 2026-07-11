import truststore; truststore.inject_into_ssl()
import os, subprocess, requests
tok=os.environ['HF_TOKEN']
base=r"D:\Coran Karim\benchmark\models"
repos={
 "whisper-tiny-ar-quran":"tarteel-ai/whisper-tiny-ar-quran",
 "whisper-medium-quran":"Habib-HF/tarbiyah-ai-whisper-medium-merged",
 "whisper-largev3turbo-quran":"MaddoggProduction/whisper-l-v3-turbo-quran-lora-dataset-mix",
}
for tag,repo in repos.items():
    d=os.path.join(base,tag); os.makedirs(d,exist_ok=True)
    r=requests.get(f'https://huggingface.co/api/models/{repo}/tree/main',
                   headers={'Authorization':f'Bearer {tok}'},timeout=30)
    files=[f['path'] for f in r.json() if f['type']=='file' and not f['path'].startswith('.git')]
    for f in files:
        url=f"https://huggingface.co/{repo}/resolve/main/{f}"
        out=os.path.join(d,f)
        print(f"DL {tag}/{f}",flush=True)
        for attempt in range(20):
            rc=subprocess.run(["curl.exe","-L","-s","--fail","-C","-","--ssl-no-revoke","-4",
                "-H",f"Authorization: Bearer {tok}","--retry","30","--retry-all-errors",
                "--retry-delay","3","--speed-limit","30000","--speed-time","20",
                "-o",out,url]).returncode
            if rc==0: print(f"  OK {f}",flush=True); break
            print(f"  retry {attempt+1} (exit {rc})",flush=True)
    print(f"[{tag}] DONE",flush=True)
print("ALL DONE",flush=True)
