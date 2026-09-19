"""Les faux signalements, mot par mot : qu'ont-ils en commun ?

On ne cherche pas a confirmer une hypothese : on mesure plusieurs proprietes du
mot et on regarde laquelle separe les mots FAUSSEMENT signales de ceux qui
passent correctement. Ce qui ne separe pas est aussi un resultat.
"""
import json, unicodedata, statistics
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "benchmark/replay_chaine_jvm_20260915"
MAN = json.loads((ROOT / "benchmark/campagne_erreurs_reelles_20260916/manifest.json").read_text(encoding="utf-8"))
CAS = {c["case_id"]: c for c in MAN["cases"]}
CFG = "vote_t3_bpe"

def base(w):
    return "".join(c for c in unicodedata.normalize("NFKD", w)
                   if unicodedata.category(c)[0] != "M" and c != "ـ").replace("ٱ", "ا")
def cle(t): return unicodedata.normalize("NFC", (t or "").replace("ـ", "").strip())
def signale(s): return s not in ("inconnu", "definitif:VERT", "provisoire:VERT")

rows = {(r["cas"], r["configuration"]): r for r in json.loads((OUT/"resultats.json").read_text(encoding="utf-8"))}

# frequence de chaque forme dans tout le corpus du banc
freq = Counter()
for c in CAS.values():
    for w in c["expected_words"]: freq[base(w)] += 1

faux, bons = [], []
for cid, cas in CAS.items():
    row = rows.get((cid, CFG)); log = OUT / f"{cid}_{CFG}.log"
    if not row or not log.exists(): continue
    mots = cas["expected_words"]; statuts = row["statuts"]
    fautes = set()
    for o in cas["operations"]: fautes.update(o["affected_word_indices"])
    # bornes des versets, pour la position dans le verset
    verset = {}
    for t in cas["timeline"]:
        for k in range(t["word_count"]): verset[t["word_start"] + k] = (k, t["word_count"])
    obs = defaultdict(list)
    for l in log.read_text(encoding="utf-8", errors="replace").splitlines():
        if "[vote-observation] " not in l: continue
        j = json.loads(l.split("[vote-observation] ", 1)[1]); obs[j["mot"]].append(j)

    for i, att in enumerate(mots):
        s = statuts.get(str(i), "inconnu")
        if s == "inconnu" or i in fautes: continue
        u = [o for o in obs[i] if o.get("interieur") and not o.get("sans_creneau") and (o.get("entendu") or "").strip()]
        a = cle(att)
        d = dict(
            cas=cid, mot=i, texte=att, statut=s,
            lettres=len(base(att)),
            dist_faute=min([abs(i - f) for f in fautes], default=99),
            pos_verset=verset.get(i, (0, 1))[0],
            fin_verset=verset.get(i, (0, 1))[1] - 1 - verset.get(i, (0, 1))[0],
            freq=freq[base(att)],
            n_obs=len(u),
            n_divergentes=sum(1 for o in u if cle(o.get("entendu")) != a),
            lu=[o.get("entendu") for o in u if cle(o.get("entendu")) != a][:2],
        )
        (faux if signale(s) else bons).append(d)

def cmp(champ, fmt="%.2f"):
    f = [x[champ] for x in faux]; b = [x[champ] for x in bons]
    print(("  %-16s faux " + fmt + "   corrects " + fmt + "   ecart " + fmt)
          % (champ, statistics.median(f), statistics.median(b),
             statistics.median(f) - statistics.median(b)))

print(f"faux signalements : {len(faux)}   mots corrects passes : {len(bons)}")
print("\n=== medianes comparees ===")
for ch in ("lettres", "dist_faute", "pos_verset", "fin_verset", "freq", "n_obs", "n_divergentes"):
    cmp(ch)

print("\n=== part des faux par distance a l'erreur injectee la plus proche ===")
for d in (0, 1, 2, 3):
    nf = sum(1 for x in faux if x["dist_faute"] == d)
    nb = sum(1 for x in bons if x["dist_faute"] == d)
    if nf + nb: print("  a %d mot(s) : %3d faux / %4d mots = %4.1f %%" % (d, nf, nf+nb, 100*nf/(nf+nb)))
lf = sum(1 for x in faux if x["dist_faute"] >= 4); lb = sum(1 for x in bons if x["dist_faute"] >= 4)
if lf+lb: print("  a 4+ mots  : %3d faux / %4d mots = %4.1f %%" % (lf, lf+lb, 100*lf/(lf+lb)))

print("\n=== part des faux par longueur du mot ===")
for lo, hi in ((0,2),(3,3),(4,4),(5,6),(7,20)):
    nf = sum(1 for x in faux if lo <= x["lettres"] <= hi)
    nb = sum(1 for x in bons if lo <= x["lettres"] <= hi)
    if nf+nb: print("  %2d-%2d lettres : %3d faux / %4d = %4.1f %%" % (lo, hi, nf, nf+nb, 100*nf/(nf+nb)))

print("\n=== mots les plus souvent faussement signales ===")
c = Counter(x["texte"] for x in faux)
for m, n in c.most_common(12):
    tot = sum(1 for x in faux + bons if x["texte"] == m)
    print("  %-16s %2d faux / %2d occurrences" % (m, n, tot))

print("\n=== echantillon ===")
for x in faux[:12]:
    print("  %-5s/%-4d %-16s %-18s obs=%d div=%d lu=%s" %
          (x["cas"], x["mot"], x["texte"], x["statut"], x["n_obs"], x["n_divergentes"], x["lu"]))
