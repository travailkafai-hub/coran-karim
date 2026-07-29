"""OU EST L'ANCRE, contre OU EN EST VRAIMENT LE RECITATEUR, seconde par seconde.

L'instrument qui manquait. Sans lui on ne sait pas dire si l'ancre est en
RETARD (le reciteur a pris de l'avance) ou en AVANCE (l'app a saute des mots
et reclame un texte pas encore recite) -- et les deux appellent des correctifs
opposes. Le 2026-07-29 j'ai passe la journee a corriger le premier cas alors
que la session mesurait le second.

Verite terrain : le decodage libre du flux BRUT sur une fenetre glissante,
apparie au texte attendu. Aucune dependance a l'app.
"""
import json,os,re,sys,glob,wave,datetime as dt
import numpy as np
sys.path.insert(0,"benchmark"); sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
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
    for a in "ٱأإآ": x=x.replace(a,"ا")
    return x.replace("ى","ي").replace(" ","")
def dec(a):
    mel=compute_mel_features(a).astype(np.float32)[None]
    lp=s.run(None,{"audio_signal":mel,"length":np.array([mel.shape[2]],dtype=np.int64)})[0][0]
    ids=lp.argmax(-1); o=[];p=-1
    for i in ids:
        if i!=p and i!=BL: o.append(vocab[i])
        p=i
    return "".join(o).replace("▁"," ").strip()
d=sys.argv[1].rstrip("/")
L=open(f"{d}/session.log",encoding="utf-8",errors="replace").read()
sr=int(re.search(r"sourate=(\d+)",L).group(1))
Q=json.load(open("app/assets/data/quran_verses.json",encoding="utf-8"))
M=[]
for v in Q:
    x,y=map(int,v["verse_key"].split(":"))
    if x==sr: M+=v["text_uthmani"].split()
st=sorted(glob.glob(f"{d}/wav/stream_*.wav"))[0]
ep=int(re.search(r"stream_(\d+)",st).group(1))/1000.
with wave.open(st,"rb") as f:
    a=np.frombuffer(f.readframes(f.getnframes()),dtype=np.int16).astype(np.float32)/32768.
# ancre de l'app au fil du temps
anc=[]
for l in L.splitlines():
    m=re.search(r"nouvelle_ancre=(\d+)",l)
    if m:
        try: anc.append((dt.datetime.fromisoformat(l.split(" ")[0]).timestamp()-ep,int(m.group(1))))
        except Exception: pass
print(f"{'t (s)':>7}{'ancre app':>11}{'reciteur reel':>15}{'ecart':>8}   texte entendu")
FEN=6.0
t=0.0
while t+FEN<=len(a)/SR:
    e=sq(dec(a[int(t*SR):int((t+FEN)*SR)]))
    # position = l'offset qui apparie le PLUS de mots CONSECUTIFS (comme le
    # resync). Un mot isole apparie n'importe ou dans la sourate -- mesure du
    # 2026-07-29 : la recherche par mot unique donnait « mot 837 » sur un
    # passage du verset 4.
    vrai=-1; best=0
    for o in range(len(M)):
        h=0; pos=0
        for w in range(o,min(len(M),o+6)):
            att=sq(M[w])
            if len(att)<3: continue
            at=e.find(att,pos)
            if at<0: break
            h+=1; pos=at+len(att)
        if h>best: best=h; vrai=o+h-1
    if best<2: vrai=-1
    ap=[v for tt,v in anc if tt<=t+FEN]
    ap=ap[-1] if ap else 0
    if vrai>=0:
        print(f"{t:>7.0f}{ap:>11}{vrai:>15}{ap-vrai:>+8}   {dec(a[int(t*SR):int((t+FEN)*SR)])[:44]}")
    t+=10.0
