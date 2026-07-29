"""Rejoue HORS DEVICE l'algorithme exact de findResyncOffset sur les
dérives réellement détectées par l'app.

Aucune approximation : le texte du décodage libre est celui écrit dans le log
par l'app elle-meme (ligne « retranscription Ns -> ... »), et l'appariement
reproduit le Kotlin a l'identique (MIN_RESYNC_HITS=3, RESYNC_WINDOW_WORDS=6,
MAX_RESYNC_LOOKAHEAD=60, harakat retirees, suite stricte).

Repond a UNE question : si le garde `isFinal` sautait, ou l'ancre atterrirait-
elle, et serait-ce au bon endroit ?
"""
import json,re,sys,glob,os
MIN_HITS=3; WIN=6; LOOK=60
HARAKAT=set(range(0x064B,0x0653))|{0x0640}
def sq(s): return "".join(c for c in s if ord(c) not in HARAKAT).replace("ٱ","ا").replace("أ","ا").replace("إ","ا").replace("آ","ا")
Q=json.load(open("app/assets/data/quran_verses.json",encoding="utf-8"))
def mots_sourate(s):
    m=[]
    for v in Q:
        a,b=map(int,v["verse_key"].split(":"))
        if a==s: m+=v["text_uthmani"].split()
    return m
def resync(entendu, mots, anchor):
    e=sq(entendu); best=(0,-1)
    for off in range(anchor, min(len(mots), anchor+LOOK)):
        hits=0; pos=0
        for w in range(off, min(len(mots), off+WIN)):
            att=sq(mots[w])
            if len(att)<2: continue
            at=e.find(att,pos)
            if at<0: break
            hits+=1; pos=at+len(att)
        if hits>best[0]: best=(hits,off)
    return best
MOTIF=sys.argv[1] if len(sys.argv)>1 else "benchmark/recettes/*-s19/"
for d in sorted(glob.glob(MOTIF)):
    log=os.path.join(d,"session.log")
    if not os.path.exists(log): continue
    lignes=open(log,encoding="utf-8",errors="replace").read().splitlines()
    ms=re.search(r"\[RECETTE\] sourate=(\d+)","\n".join(lignes[:80]))
    mots=mots_sourate(int(ms.group(1)) if ms else 19)
    cas=[]
    dernier_txt=None
    for i,l in enumerate(lignes):
        m=re.search(r'retranscription \d+s -> \d+ms : "([^"]*)"',l)
        if m: dernier_txt=m.group(1)
        if "ANCRE A LA DERIVE" in l:
            # ancre courante = derniere ligne « alignement ... ancre=N »
            anc=None
            for j in range(i,max(0,i-40),-1):
                a=re.search(r"alignement seq=\d+ ancre=(\d+)",lignes[j])
                if a: anc=int(a.group(1)); break
            if anc is None or not dernier_txt: continue
            cas.append((anc,dernier_txt))
    if not cas: continue
    print(f"\n=== {os.path.basename(d.rstrip('/'))} — {len(cas)} derive(s) ===")
    for anc,txt in cas:
        hits,off=resync(txt,mots,anc)
        agit = hits>=MIN_HITS and off>anc
        print(f"  ancre={anc:<3} entendu=\"{txt[:46]}\"")
        print(f"     -> {hits} mots apparies a l'offset {off}  |  "
              f"{'RESYNC : ancre '+str(anc)+' -> '+str(off)+f' (+{off-anc})' if agit else 'aucune action'}")
        if agit: print(f"     mots vises : {' '.join(mots[off:off+4])}")
