"""Le modele lit-il mieux selon la PLACE du mot dans la fenetre ?

Si la meme chaine lit correctement un mot dans une fenetre et mal dans une
autre, ce n'est pas le modele qui echoue : ce sont les conditions d'ecoute.
On mesure donc, OBSERVATION par OBSERVATION (pas mot par mot), le taux de
lecture divergente selon le contexte dont le modele disposait.
"""
import json, unicodedata
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "benchmark/replay_chaine_jvm_20260915"
MAN = json.loads((ROOT/"benchmark/campagne_erreurs_reelles_20260916/manifest.json").read_text(encoding="utf-8"))
CAS = {c["case_id"]: c for c in MAN["cases"]}
def cle(t): return unicodedata.normalize("NFC", (t or "").replace("ـ","").strip())

ctx_av, ctx_ap, largeur, place = Counter(), Counter(), Counter(), Counter()
tot = Counter()
for cid, cas in CAS.items():
    log = OUT / f"{cid}_vote_t3_bpe.log"
    if not log.exists(): continue
    mots = cas["expected_words"]
    fautes = set()
    for o in cas["operations"]: fautes.update(o["affected_word_indices"])
    for l in log.read_text(encoding="utf-8", errors="replace").splitlines():
        if "[vote-observation] " not in l: continue
        j = json.loads(l.split("[vote-observation] ", 1)[1])
        i = j["mot"]
        # UNIQUEMENT les mots corrects : on mesure la qualite de lecture,
        # pas la detection. Une divergence ici est une erreur de lecture.
        if i in fautes or i >= len(mots): continue
        if not j.get("interieur") or j.get("sans_creneau"): continue
        lu = (j.get("entendu") or "").strip()
        if not lu: continue
        fd, ff = j.get("fenetre_debut") or 0, j.get("fenetre_fin") or 0
        d, f = j["debut"], j["fin"]
        if ff <= fd: continue
        avant = (d - fd) / 16000.0          # secondes de contexte avant le mot
        apres = (ff - f) / 16000.0          # secondes apres
        larg  = (ff - fd) / 16000.0
        pos   = (d - fd) / max(1.0, float(ff - fd))   # 0 = debut de fenetre, 1 = fin
        mauvais = cle(lu) != cle(mots[i])
        def bucket(v, bornes):
            for b in bornes:
                if v < b: return f"< {b}"
            return f">= {bornes[-1]}"
        ctx_av[(bucket(avant,[0.5,1.0,2.0,3.0]), mauvais)] += 1
        ctx_ap[(bucket(apres,[0.5,1.0,2.0,3.0]), mauvais)] += 1
        largeur[(bucket(larg,[3.0,4.0,5.0,6.0]), mauvais)] += 1
        place[(bucket(pos,[0.2,0.4,0.6,0.8]), mauvais)] += 1
        tot[mauvais] += 1

def montre(titre, c, unite=""):
    print(f"\n=== {titre} ===")
    cles = sorted({k[0] for k in c}, key=lambda s: (s.startswith(">="), float(s.split()[-1])))
    for k in cles:
        m, b = c[(k, True)], c[(k, False)]
        if m + b < 15: continue
        print("  %-8s %-3s  %4d mal lus / %5d = %5.1f %%" % (k, unite, m, m+b, 100*m/(m+b)))

print(f"observations de mots CORRECTS : {tot[True]+tot[False]}  "
      f"dont mal lues : {tot[True]} ({100*tot[True]/max(tot[True]+tot[False],1):.1f} %)")
montre("contexte AVANT le mot", ctx_av, "s")
montre("contexte APRES le mot", ctx_ap, "s")
montre("largeur de la fenetre", largeur, "s")
montre("place du mot dans la fenetre (0=debut, 1=fin)", place)
