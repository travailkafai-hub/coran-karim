# -*- coding: utf-8 -*-
"""Etape 7 : LE CONTENU REEL des 91 commits de la chaine.
- corps de message (%b) : c'est la que vivent les MESURES
- symboles des diffs : ce que le commit FAIT vraiment
Rien n'est devine."""
import json, re, subprocess
from pathlib import Path
ROOT = Path("/media/kafai/NouveauNom/Coran Karim")
SRC = str(ROOT/"graphify-out/git_history_all_branches.md")
CH = ["app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer",
      "app/lib/providers/recitation_provider.dart",
      "app/lib/services/recitation_verifier.dart",
      "app/lib/services/fastconformer_verifier.dart"]
def git(*a):
    return subprocess.run(["git"]+list(a),cwd=ROOT,capture_output=True,text=True,errors="ignore").stdout

st = json.loads(Path("/tmp/gen/state5.json").read_text(encoding="utf-8"))
nodes, edges, hyper = st["nodes"], st["edges"], st["hyperedges"]
seen = {n["id"] for n in nodes}
byid = {n["id"]: n for n in nodes}
def N(i,l,t,s,loc=None,**x):
    if i in seen: return i
    seen.add(i); d={"id":i,"label":l,"file_type":t,"source_file":s,"source_location":loc,
    "source_url":None,"captured_at":None,"author":None,"contributor":None}; d.update(x)
    nodes.append(d); byid[i]=d; return i
def E(s,t,r,c,sc,sf,loc=None,w=1.0):
    if s in seen and t in seen:
        edges.append({"source":s,"target":t,"relation":r,"confidence":c,"confidence_score":sc,
                      "source_file":sf,"source_location":loc,"weight":w})

audit = json.loads(Path("/tmp/gen/audit.json").read_text(encoding="utf-8"))
pc = audit["per_commit"]

is_const = lambda k: bool(re.fullmatch(r'[A-Z][A-Z0-9_]{3,}',k)) or bool(re.fullmatch(r'_k[A-Z]\w+',k))
is_fun   = lambda k: len(k)>4 and not k.isupper()

# --- 1. CORPS DE MESSAGE : injecte dans le rationale du commit (les MESURES)
RE_MES = re.compile(r'(\d+[,.]\d+\s*%|\d+\s*%|\d+[,.]\d+\s*(?:s|ms|pt|nats)|\b\d+\s*/\s*\d+\b|->|→)')
nmes = 0
for h, info in pc.items():
    cid = f"commit_{h}"
    if cid not in seen: continue
    body = git("show","-s","--format=%b",h).strip()
    lignes_mesure = [l.strip() for l in body.splitlines() if RE_MES.search(l) and len(l.strip())>25]
    n = byid[cid]
    base = n.get("rationale") or info["sujet"]
    if body:
        n["rationale"] = (base + "\n\nCORPS : " + body[:1500])
    if lignes_mesure:
        n["rationale"] = n.get("rationale","") + "\n\nMESURES : " + " || ".join(lignes_mesure[:6])[:900]
        nmes += 1
    # fichiers reellement touches
    n["fichiers"] = git("show","--stat","--format=","--name-only",h,"--",*CH).split()

# --- 2. SYMBOLES REELS DU DIFF : commit -> symbole, avec le SENS (ajout/retrait)
nsym = 0
for h, info in pc.items():
    cid = f"commit_{h}"
    if cid not in seen: continue
    for kind, key, rel, sens in (("const","const_add","implements","AJOUTE"),
                                 ("const","const_del","implements","SUPPRIME"),
                                 ("fun","fun_add","calls","AJOUTE"),
                                 ("fun","fun_del","calls","SUPPRIME")):
        for sym in info[key]:
            ok = is_const(sym) if kind=="const" else is_fun(sym)
            if not ok: continue
            # rattacher a la variable/fonction DEJA dans le graphe si elle existe
            cand = f"var_{sym.lower().lstrip('_')}" if kind=="const" else None
            if cand and cand in seen:
                tgt = cand
            else:
                tgt = f"sym_{kind}_{re.sub(r'[^a-z0-9]+','_',sym.lower())}"
                N(tgt, f"{sym} ({'constante' if kind=='const' else 'fonction'})", "code", SRC,
                  rationale=f"Symbole {kind} touche par au moins un commit de la chaine.")
            E(cid, tgt, "shares_data_with", "EXTRACTED", 1.0, SRC, loc=sens)
            nsym += 1

# --- 3. COUPLAGE REEL : deux commits qui touchent le MEME symbole
import itertools
hist = {}
for h, info in pc.items():
    for key in ("const_add","const_del","fun_add","fun_del"):
        for sym in info[key]:
            if is_const(sym) or is_fun(sym):
                hist.setdefault(sym, set()).add(h)
ncoup = 0
for sym, hs in hist.items():
    hs = sorted(hs)
    if not (2 <= len(hs) <= 8): continue
    for a, b in itertools.combinations(hs, 2):
        if f"commit_{a}" in seen and f"commit_{b}" in seen:
            E(f"commit_{a}", f"commit_{b}", "semantically_similar_to", "EXTRACTED", 1.0, SRC,
              loc=f"touchent tous deux {sym}")
            ncoup += 1

print(f"[7] Corps de message injectes : {len(pc)}  (dont {nmes} avec des MESURES chiffrees)")
print(f"    Aretes commit->symbole reel : {nsym}")
print(f"    Couplages commit<->commit par symbole PARTAGE : {ncoup}")
print(f"    Total : {len(nodes)} noeuds, {len(edges)} aretes")
Path("/tmp/gen/state7.json").write_text(json.dumps(
    {"nodes":nodes,"edges":edges,"hyperedges":hyper}, ensure_ascii=False), encoding="utf-8")
