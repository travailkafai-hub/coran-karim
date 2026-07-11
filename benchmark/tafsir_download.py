"""Download Quran explanations for the Gemma tutor dataset:
   - Arabic tafsirs (Muyassar, Ibn Kathir, Saadi) via per-ayah endpoint
   - English tafsirs (Ibn Kathir, Maarif) via per-ayah endpoint
   - French translations (Hamidullah, Montada, Rashid Maash) via bulk endpoint
Saves to data/tafsir/*.jsonl  (one line per verse: {verse_key, text})
"""
import truststore; truststore.inject_into_ssl()
import os, json, re, requests
from concurrent.futures import ThreadPoolExecutor, as_completed
ROOT=os.path.dirname(os.path.abspath(__file__))
OUT=os.path.join(ROOT,"data","tafsir"); os.makedirs(OUT,exist_ok=True)

AR_TAFSIR={"ar-muyassar":16,"ar-ibn-kathir":14,"ar-saadi":91}
EN_TAFSIR={"en-ibn-kathir":169,"en-maarif":168}
FR_TRANS ={"fr-hamidullah":31,"fr-montada":136,"fr-rashid-maash":779}

def clean(t):
    if not t: return ""
    t=re.sub(r"<sup[^>]*>.*?</sup>","",t,flags=re.S)
    t=re.sub(r"<[^>]+>"," ",t)
    return re.sub(r"\s+"," ",t).strip()

# all verse keys
verses=requests.get("https://api.quran.com/api/v4/quran/verses/uthmani",timeout=60).json()["verses"]
keys=[v["verse_key"] for v in verses]
print(f"{len(keys)} versets",flush=True)

def dl_tafsir(slug,tid):
    path=os.path.join(OUT,slug+".jsonl")
    if os.path.exists(path) and sum(1 for _ in open(path,encoding="utf-8"))>=6000:
        print(f"  skip {slug} (deja)",flush=True); return
    res={}
    def one(k):
        for _ in range(3):
            try:
                j=requests.get(f"https://api.quran.com/api/v4/tafsirs/{tid}/by_ayah/{k}",timeout=30).json()
                return k, clean(j.get("tafsir",{}).get("text",""))
            except Exception: pass
        return k,""
    with ThreadPoolExecutor(max_workers=16) as ex:
        for k,txt in ex.map(one,keys): res[k]=txt
    with open(path,"w",encoding="utf-8") as f:
        for k in keys:
            if res.get(k): f.write(json.dumps({"verse_key":k,"text":res[k]},ensure_ascii=False)+"\n")
    print(f"  OK {slug}: {sum(1 for v in res.values() if v)} versets",flush=True)

def dl_trans(slug,tid):
    path=os.path.join(OUT,slug+".jsonl")
    arr=requests.get(f"https://api.quran.com/api/v4/quran/translations/{tid}",timeout=90).json()["translations"]
    with open(path,"w",encoding="utf-8") as f:
        for k,t in zip(keys,arr):
            txt=clean(t.get("text",""))
            if txt: f.write(json.dumps({"verse_key":k,"text":txt},ensure_ascii=False)+"\n")
    print(f"  OK {slug}: {len(arr)} versets",flush=True)

print("== Traductions FR (bulk) ==",flush=True)
for slug,tid in FR_TRANS.items(): dl_trans(slug,tid)
print("== Tafsir EN (par verset) ==",flush=True)
for slug,tid in EN_TAFSIR.items(): dl_tafsir(slug,tid)
print("== Tafsir AR (par verset) ==",flush=True)
for slug,tid in AR_TAFSIR.items(): dl_tafsir(slug,tid)
print("TAFSIR DONE",flush=True)
