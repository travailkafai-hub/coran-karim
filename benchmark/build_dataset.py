"""Build fine-tuning dataset: last 3 Hizb (72:1-114:6) x 13 reciters.
Downloads mp3 from everyayah + reference text from quran.com, writes manifest.jsonl.
"""
import truststore; truststore.inject_into_ssl()
import os, json, requests, soundfile as sf
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT  = os.path.join(ROOT, "data", "train")
os.makedirs(OUT, exist_ok=True)

RECITERS = [
    # Murattal (1 par récitateur, débit le plus élevé)
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
    # Mujawwad (style mélodique, voix distinctes)
    "Abdul_Basit_Mujawwad_128kbps","Husary_Mujawwad_64kbps","Minshawy_Mujawwad_192kbps"]
HIZBS = (58,59,60)
EVERYAYAH = "https://everyayah.com/data/{rec}/{s:03d}{a:03d}.mp3"

# 1) reference text for all verses
print("Fetching verse texts...", flush=True)
verses = {}
for hz in HIZBS:
    r = requests.get(f"https://api.quran.com/api/v4/verses/by_hizb/{hz}?fields=text_uthmani&per_page=300",timeout=30).json()
    for v in r["verses"]:
        s,a = v["verse_key"].split(":")
        verses[v["verse_key"]] = {"surah":int(s),"ayah":int(a),"text":v["text_uthmani"]}
print(f"  {len(verses)} verses", flush=True)

# 2) download all (reciter, verse) mp3s
def dl(rec, key, info):
    d = os.path.join(OUT, rec); os.makedirs(d, exist_ok=True)
    path = os.path.join(d, key.replace(":","_")+".mp3")
    if os.path.exists(path) and os.path.getsize(path)>1000:
        return ("skip", rec, key, path)
    url = EVERYAYAH.format(rec=rec, s=info["surah"], a=info["ayah"])
    for _ in range(4):
        try:
            r = requests.get(url, timeout=30)
            if r.status_code==200 and len(r.content)>1000:
                open(path,"wb").write(r.content); return ("ok", rec, key, path)
        except Exception: pass
    return ("fail", rec, key, url)

tasks = [(rec,key,info) for rec in RECITERS for key,info in verses.items()]
print(f"Downloading {len(tasks)} clips...", flush=True)
done=fail=0
with ThreadPoolExecutor(max_workers=24) as ex:
    futs=[ex.submit(dl,*t) for t in tasks]
    for i,f in enumerate(as_completed(futs)):
        st=f.result()[0]
        if st=="fail": fail+=1
        else: done+=1
        if (i+1)%1000==0: print(f"  {i+1}/{len(tasks)} (fail={fail})", flush=True)
print(f"Downloaded: {done}, failed: {fail}", flush=True)

# 3) manifest with duration filter (<=30s)
print("Building manifest...", flush=True)
manifest=[]; skipped_long=0
for rec in RECITERS:
    for key,info in verses.items():
        path = os.path.join(OUT, rec, key.replace(":","_")+".mp3")
        if not os.path.exists(path): continue
        try:
            inf = sf.info(path); dur = inf.frames/inf.samplerate
        except Exception:
            continue
        if dur>30: skipped_long+=1; continue
        manifest.append({"key":key,"reciter":rec,
                         "mp3":os.path.relpath(path,ROOT).replace("\\","/"),
                         "text":info["text"],"duration":round(dur,2)})
with open(os.path.join(ROOT,"data","manifest.jsonl"),"w",encoding="utf-8") as f:
    for m in manifest: f.write(json.dumps(m,ensure_ascii=False)+"\n")
print(f"Manifest: {len(manifest)} clips (skipped {skipped_long} >30s)", flush=True)
print("DATASET DONE", flush=True)
