#!/usr/bin/env python3
"""Taux de mots NON VERTS d'une session, compte correctement.

DEUX PIEGES, TOUS DEUX TOMBES POUR DE VRAI LE 2026-07-29 :

1. LE MOT SAUTE. Un mot enjambe par un deplacement d'ancre n'a NI ligne [GOP],
   NI ligne NON JUGE : il quitte le denominateur au lieu de compter comme
   echec. Compter « non verts / mots juges » fait BAISSER le taux a chaque mot
   perdu. On compte donc sur l'ancre max, et on liste les indices manquants.

2. DEUX RECITATIONS DANS UN MEME FICHIER. Le log est en ANNEXE : il garde la
   fin de la recitation precedente. Prendre le max de l'ancre sur tout le
   fichier fait heriter de l'ancre de la precedente -- et transforme en
   « 91 mots sautes » des mots qui n'ont simplement jamais ete recites. Une
   remise a zero (`alignement seq=1` ou `ancre=0` apres une ancre haute) marque
   une nouvelle recitation : on ne garde que la DERNIERE.
   C'est ce piege qui a fabrique de fausses regressions massives (v10 a v15
   annonces a 23-49 % de non verts) dans la premiere synthese du 2026-07-29.
"""
import re,sys,os,glob

def derniere_recitation(lignes):
    """Indice de debut de la derniere recitation (remise a zero de l'ancre)."""
    debut=0; haute=False
    for i,l in enumerate(lignes):
        m=re.search(r"alignement seq=(\d+) ancre=(\d+)",l)
        if not m: continue
        seq,anc=int(m.group(1)),int(m.group(2))
        if haute and (seq<=1 or anc==0): debut=i; haute=False
        if anc>5: haute=True
    return debut

def analyser(chemin):
    TOUT=open(chemin,encoding="utf-8",errors="replace").read().splitlines()
    L=TOUT[derniere_recitation(TOUT):]
    lock={}; nj=set()
    for l in L:
        if "secours:" in l: continue
        m=re.search(r'\[GOP\] mot=(\d+) "([^"]*)"',l)
        if not m: continue
        k=int(m.group(1))
        if "NON JUG" in l: nj.add(k)
        s=re.search(r"WordStatus\.(\w+) \(lock=true",l)
        if s: lock[k]=s.group(1)
    anc=[int(x) for x in re.findall(r"nouvelle_ancre=(\d+)","\n".join(L))]
    if not anc: return None
    amax=max(anc); vus=set(lock)|nj
    verts={k for k,v in lock.items() if v=="correct"}
    sautes=[k for k in range(amax+1) if k not in vus]
    nv=(len(vus)-len(verts))+len(sautes)
    # le tag de build est ecrit en TETE DE FICHIER, donc avant la derniere
    # recitation : le chercher dans L le rendrait introuvable.
    b=re.search(r"build=(\S+)","\n".join(TOUT))
    return dict(build=b.group(1) if b else "?", ancre=amax+1, verts=len(verts),
                signales=len(lock)-len(verts), non_juges=len(nj-set(lock)),
                sautes=sautes, non_verts=nv, taux=nv/(amax+1)*100)

if __name__=="__main__":
    for d in (sys.argv[1:] or sorted(glob.glob("benchmark/recettes/*/"))):
        p=os.path.join(d,"session.log")
        if not os.path.exists(p) or os.path.getsize(p)==0: continue
        r=analyser(p)
        if not r or r["ancre"]<20: continue
        print(f"{os.path.basename(d.rstrip('/')):<24}{r['build']:<28}"
              f"ancre={r['ancre']:<4} verts={r['verts']:<4} sign={r['signales']:<3} "
              f"nonJ={r['non_juges']:<3} sautes={len(r['sautes']):<3} "
              f"-> {r['non_verts']:>3}/{r['ancre']} = {r['taux']:5.2f} %")
