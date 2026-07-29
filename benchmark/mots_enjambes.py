"""Les mots que le resync enjamberait sont-ils RECUPERABLES ?

Le resync debloque l'ancre mais marque « jamais juges » les mots enjambes.
Question de l'utilisateur : un second buffer pourrait-il les rattraper ?
Reponse mesurable : ces mots sont-ils presents dans le flux BRUT ? S'ils y
sont, un rejeu cible peut les juger ; s'ils n'y sont pas, aucune couche ne
les recuperera jamais et le resync est la meilleure issue possible.
"""
import json,os,re,sys,glob,wave
import numpy as np
sys.path.insert(0,"benchmark")
from mel_numpy_reference import compute_mel_features
import onnxruntime as ort
SR=16000; C=os.path.expanduser("~/.cache/coran-karim")
V=json.load(open(f"{C}/dev_vocab.json",encoding="utf-8"))
vocab=[k for k,_ in sorted(V.items(),key=lambda kv:kv[1])] if isinstance(V,dict) else V
BL=len(vocab)
s=ort.InferenceSession(f"{C}/dev_model.onnx",providers=["CPUExecutionProvider"])
HAR=set(range(0x064B,0x0653))|{0x0640}
def sq(x):
    x="".join(c for c in x if ord(c) not in HAR)
    for a,b in (("ٱا","ا"),("أا","ا"),("إا","ا"),("آا","ا"),("ىي","ي")):
        x=x.replace(a[0],a[1])
    return x.replace(" ","")
def dec(a):
    if len(a)<SR//2: return ""
    mel=compute_mel_features(a).astype(np.float32)[None]
    lp=s.run(None,{"audio_signal":mel,"length":np.array([mel.shape[2]],dtype=np.int64)})[0][0]
    ids=lp.argmax(-1); o=[];p=-1
    for i in ids:
        if i!=p and i!=BL: o.append(vocab[i])
        p=i
    return "".join(o).replace("▁"," ").strip()
Q=json.load(open("app/assets/data/quran_verses.json",encoding="utf-8"))
def mots(sr):
    m=[]
    for v in Q:
        a,b=map(int,v["verse_key"].split(":"))
        if a==sr: m+=v["text_uthmani"].split()
    return m
# cas mesures par simuler_resync.py sur Maryam
CAS=[("20260729-013154-s19",19,25,31),("20260729-013154-s19",19,47,52),
     ("20260729-014254-s19",19,25,30),("20260729-014254-s19",19,47,59),
     ("20260729-012601-s19",19,47,61)]
tot=trouve=0
CACHE={}
for sess,sr,anc,off in CAS:
    w=glob.glob(f"benchmark/recettes/{sess}/wav/stream_*.wav")
    if not w: continue
    with wave.open(sorted(w)[0],"rb") as f:
        a=np.frombuffer(f.readframes(f.getnframes()),dtype=np.int16).astype(np.float32)/32768.
    M=mats=mots(sr); enj=M[anc:off]
    if sess not in CACHE:
        vues=[]
        for win in (3,6):
            t=0.0
            while t+win<=len(a)/SR:
                vues.append((win,t,sq(dec(a[int(t*SR):int((t+win)*SR)])))); t+=win/2
        CACHE[sess]=vues
    vues=CACHE[sess]
    print(f"\n=== {sess} : ancre {anc} -> {off} ({len(enj)} mots enjambes) ===")
    for k,mot in enumerate(enj):
        cible=sq(mot); ok=None
        for win,t,txt in vues:
            if cible in txt: ok=(win,t); break
        tot+=1; trouve+= ok is not None
        print(f"   {anc+k:>3} {mot:<16} " + (f"PRESENT dans le flux brut a {ok[1]:.0f}s (fenetre {ok[0]}s) -> RECUPERABLE" if ok else "ABSENT du flux brut -> definitivement perdu"))
print(f"\n{'='*64}\nMOTS ENJAMBES : {tot} | presents dans le flux brut : {trouve} = {trouve/max(tot,1)*100:.0f} %")
