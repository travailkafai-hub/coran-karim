"""LA REGLE « ne rien deviner » vaut-elle mieux que le detecteur a seuils ?

Pour CHAQUE derive detectee par l'app dans TOUTES les sessions du depot :
  1. on reconstruit l'audio exact du segment (flux brut + horodatage),
  2. on calcule l'offset propose par le decodage libre (algorithme du device),
  3. on aligne aux DEUX positions et on compare les scores,
  4. on compte les decisions que la comparaison aurait prises.

Le detecteur a seuils dit « derive » a chaque fois. La regle par comparaison,
elle, peut dire non. On mesure donc combien de ses « non » sont justifies.
"""
import json,os,re,sys,glob,wave,datetime as dt
import numpy as np
sys.path.insert(0,"benchmark"); sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from mel_numpy_reference import compute_mel_features
from outils_tok import tok_actuel,viterbi,logsoftmax
import onnxruntime as ort
SR=16000; C=os.path.expanduser("~/.cache/coran-karim")
sess=ort.InferenceSession(f"{C}/dev_model.onnx",providers=["CPUExecutionProvider"])
Q=json.load(open("app/assets/data/quran_verses.json",encoding="utf-8"))
HAR=set(range(0x064B,0x0653))|{0x0640}
def sq(x):
    x="".join(c for c in x if ord(c) not in HAR)
    for a in "ٱأإآ": x=x.replace(a,"ا")
    return x.replace("ى","ي").replace(" ","")
def mots(sr):
    m=[]
    for v in Q:
        a,b=map(int,v["verse_key"].split(":"))
        if a==sr: m+=v["text_uthmani"].split()
    return m
def resync(ent,M,anc,LOOK=60,WIN=6):
    e=sq(ent); best=(0,-1)
    for off in range(anc,min(len(M),anc+LOOK)):
        h=0;p=0
        for w in range(off,min(len(M),off+WIN)):
            a=sq(M[w])
            if len(a)<2: continue
            at=e.find(a,p)
            if at<0: break
            h+=1;p=at+len(a)
        if h>best[0]: best=(h,off)
    return best
def lps(a):
    mel=compute_mel_features(a).astype(np.float32)[None]
    lg=sess.run(None,{"audio_signal":mel,"length":np.array([mel.shape[2]],dtype=np.int64)})[0][0]
    return logsoftmax(lg.astype(np.float64))
def score(lp,lst):
    toks=[];bor=[]
    for w in lst:
        t=tok_actuel(w); bor.append((len(toks),len(toks)+len(t))); toks+=t
    if not toks: return -99.
    sc,fr,sct=viterbi(lp,toks)
    return sc/max(sum(fr),1)
bouge=reste=0; gains=[]; details=[]
for d in sorted(glob.glob("benchmark/recettes/*/")):
    lg=os.path.join(d,"session.log")
    st=glob.glob(os.path.join(d,"wav","stream_*.wav"))
    if not(os.path.exists(lg) and st): continue
    L=open(lg,encoding="utf-8",errors="replace").read().splitlines()
    ms=re.search(r"\[RECETTE\] sourate=(\d+)","\n".join(L[:80]))
    if not ms: continue
    M=mots(int(ms.group(1)))
    ep=int(re.search(r"stream_(\d+)",st[0]).group(1))/1000.0
    audio=None
    for i,l in enumerate(L):
        if "ANCRE A LA DERIVE" not in l: continue
        anc=txt=dur=None
        for j in range(i,max(0,i-40),-1):
            m=re.search(r"alignement seq=\d+ ancre=(\d+)",L[j])
            if m and anc is None: anc=int(m.group(1))
            m=re.search(r'retranscription (\d+)s -> \d+ms : "([^"]*)"',L[j])
            if m and txt is None: dur=int(m.group(1)); txt=m.group(2)
            if anc is not None and txt is not None: break
        if anc is None or txt is None: continue
        h,off=resync(txt,M,anc)
        if h<3 or off<=anc: continue
        if audio is None:
            with wave.open(st[0],"rb") as f:
                audio=np.frombuffer(f.readframes(f.getnframes()),dtype=np.int16).astype(np.float32)/32768.
        fin=dt.datetime.fromisoformat(l.split(" ")[0]).timestamp()-ep; deb=max(0.,fin-dur)
        seg=audio[int(deb*SR):int(fin*SR)]
        if len(seg)<SR: continue
        lp=lps(seg)
        sa=score(lp,M[anc:anc+10]); sb=score(lp,M[off:off+10])
        if sb>sa: bouge+=1; gains.append(sb-sa)
        else: reste+=1
        details.append((os.path.basename(d.rstrip('/')),anc,off,sa,sb,sb>sa))
print(f"{'session':<24}{'ancre':>6}{'->':>4}{'offset':>7}{'bloquee':>10}{'corrigee':>10}  decision")
for n,a,o,sa,sb,mv in details:
    print(f"{n:<24}{a:>6}{'->':>4}{o:>7}{sa:>10.2f}{sb:>10.2f}  {'DEPLACE' if mv else 'refuse (ancre saine)'}")
print(f"\n{'='*72}")
print(f"derives examinees : {bouge+reste}")
print(f"   ancre deplacee : {bouge}  (gain moyen de score/frame : +{np.mean(gains):.2f})" if gains else "")
print(f"   deplacement REFUSE par la mesure : {reste}  <- autant de faux positifs du detecteur a seuils")
