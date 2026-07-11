"""Download the FULL Quran (6236 verses) x 41 reciters for step-3 fine-tuning.
mp3 only (wav conversion deferred). Resumable (skips existing). Writes manifest_full.jsonl.
"""
import truststore; truststore.inject_into_ssl()
import os, json, requests
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT  = os.path.join(ROOT, "data", "train")
os.makedirs(OUT, exist_ok=True)

RECITERS = [
    "Alafasy_128kbps","Husary_128kbps","Minshawy_Murattal_128kbps","Abdul_Basit_Murattal_192kbps",
    "Abdurrahmaan_As-Sudais_192kbps","Saood_ash-Shuraym_128kbps","Hudhaify_128kbps","Ghamadi_40kbps",
    "Muhammad_Ayyoub_128kbps","Abu_Bakr_Ash-Shaatree_128kbps","Ahmed_ibn_Ali_al_Ajamy_128kbps",
    "Hani_Rifai_192kbps","Mohammad_al_Tablaway_128kbps","Abdullah_Basfar_192kbps",
    "Abdullaah_3awwaad_Al-Juhaynee_128kbps","Ahmed_Neana_128kbps","Akram_AlAlaqimy_128kbps",
    "Ali_Hajjaj_AlSuesy_128kbps","Ayman_Sowaid_64kbps","Fares_Abbad_64kbps","Ibrahim_Akhdar_32kbps",
    "Karim_Mansoori_40kbps","Khaalid_Abdullaah_al-Qahtaanee_192kbps","Maher_AlMuaiqly_64kbps",
    "Muhammad_AbdulKareem_128kbps","Muhammad_Jibreel_128kbps","Mustafa_Ismail_48kbps",
    "Nasser_Alqatami_128kbps","Yaser_Salamah_128kbps","Yasser_Ad-Dussary_128kbps","aziz_alili_128kbps",
    "mahmoud_ali_al_banna_32kbps","khalefa_al_tunaiji_64kbps","Sahl_Yassin_128kbps",
    "Salaah_AbdulRahman_Bukhatir_128kbps","Salah_Al_Budair_128kbps","Ali_Jaber_64kbps","Muhsin_Al_Qasim_192kbps",
    "Abdul_Basit_Mujawwad_128kbps","Husary_Mujawwad_64kbps","Minshawy_Mujawwad_192kbps"]
EVERYAYAH = "https://everyayah.com/data/{rec}/{s:03d}{a:03d}.mp3"

print("Fetching ALL verse texts...", flush=True)
r = requests.get("https://api.quran.com/api/v4/quran/verses/uthmani", timeout=60).json()
verses = {}
for v in r["verses"]:
    s,a = v["verse_key"].split(":")
    verses[v["verse_key"]] = {"surah":int(s),"ayah":int(a),"text":v["text_uthmani"]}
print(f"  {len(verses)} verses", flush=True)

def dl(rec, key, info):
    d = os.path.join(OUT, rec); os.makedirs(d, exist_ok=True)
    path = os.path.join(d, key.replace(":","_")+".mp3")
    if os.path.exists(path) and os.path.getsize(path)>1000: return "skip"
    url = EVERYAYAH.format(rec=rec, s=info["surah"], a=info["ayah"])
    for _ in range(4):
        try:
            rr = requests.get(url, timeout=30)
            if rr.status_code==200 and len(rr.content)>1000:
                open(path,"wb").write(rr.content); return "ok"
        except Exception: pass
    return "fail"

tasks = [(rec,key,info) for rec in RECITERS for key,info in verses.items()]
print(f"Total target: {len(tasks)} clips ({len(RECITERS)} reciters x {len(verses)} verses)", flush=True)
done=skip=fail=0
with ThreadPoolExecutor(max_workers=24) as ex:
    futs=[ex.submit(dl,*t) for t in tasks]
    for i,f in enumerate(as_completed(futs)):
        st=f.result()
        if st=="fail": fail+=1
        elif st=="skip": skip+=1
        else: done+=1
        if (i+1)%5000==0: print(f"  {i+1}/{len(tasks)}  new={done} skip={skip} fail={fail}", flush=True)
print(f"Done. new={done} skip={skip} fail={fail}", flush=True)

# manifest (mp3 paths; duration filter happens at wav-conversion step-3)
manifest=[]
for rec in RECITERS:
    for key,info in verses.items():
        path=os.path.join(OUT,rec,key.replace(":","_")+".mp3")
        if os.path.exists(path) and os.path.getsize(path)>1000:
            manifest.append({"key":key,"reciter":rec,
                "mp3":os.path.relpath(path,ROOT).replace("\\","/"),"text":info["text"]})
with open(os.path.join(ROOT,"data","manifest_full.jsonl"),"w",encoding="utf-8") as f:
    for m in manifest: f.write(json.dumps(m,ensure_ascii=False)+"\n")
print(f"manifest_full.jsonl: {len(manifest)} clips", flush=True)
print("FULL DATASET DONE", flush=True)
