"""Combien d'audio la purge-quand-rien-n'est-place detruit-elle ?

BufferedTranscriber ~2099 : si la passe finale ne place aucun mot, TOUT le
buffer est purge (pour ne pas figer la session). Ce banc chiffre le prix de ce
choix sur toutes les sessions du depot : secondes jetees, et surtout ce que les
APERCUS avaient trouve dans cet audio avant qu'il soit detruit.

Lecture seule sur les logs -- aucune dependance au device.
"""
import glob,os,re,sys
tot_ms=tot_gels=tot_sess=0
tot_apercu_mots=0
lignes=[]
for d in sorted(glob.glob("benchmark/recettes/*/")):
    p=os.path.join(d,"session.log")
    if not os.path.exists(p): continue
    L=open(p,encoding="utf-8",errors="replace").read().splitlines()
    ms=gels=apm=0
    dernier_final_vide=False; meilleur_apercu=0
    for i,l in enumerate(L):
        m=re.search(r"alignement seq=\d+ ancre=(\d+).*final=(true|false) mots=(\d+).*derniere_frame=(-?\d+)",l)
        if m:
            fin=m.group(2)=="true"; mots=int(m.group(3)); df=int(m.group(4))
            if fin: dernier_final_vide = (df < 0)
            else: meilleur_apercu=max(meilleur_apercu,mots)
        g=re.search(r"segment FIGE.*consomme=(\d+)ms conserve=(\d+)ms",l)
        if g and dernier_final_vide:
            ms+=int(g.group(1)); gels+=1; apm+=meilleur_apercu
            meilleur_apercu=0; dernier_final_vide=False
    if gels:
        tot_ms+=ms; tot_gels+=gels; tot_sess+=1; tot_apercu_mots+=apm
        lignes.append((os.path.basename(d.rstrip('/')),gels,ms/1000.0,apm))
lignes.sort(key=lambda x:-x[2])
print(f"{'session':<26}{'gels a vide':>12}{'audio jete':>12}{'mots vus par apercu':>22}")
for n,g,s_,a in lignes[:12]:
    print(f"{n:<26}{g:>12}{s_:>10.1f} s{a:>22}")
print(f"\n{'='*72}")
print(f"sessions concernees : {tot_sess} | gels a vide : {tot_gels}")
print(f"AUDIO DETRUIT : {tot_ms/1000:.0f} s au total, soit {tot_ms/1000/max(tot_gels,1):.1f} s par gel")
print(f"MOTS que les apercus avaient DEJA trouves dans cet audio : {tot_apercu_mots}")
