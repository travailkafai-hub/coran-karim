# -*- coding: utf-8 -*-
"""CONTROLE : lit le DIFF REEL de chacun des 91 commits de la chaine.
Extrait les fonctions et constantes AJOUTEES (+) et SUPPRIMEES (-).
Rien n'est devine : tout vient de `git show`."""
import re, subprocess, json
from collections import defaultdict
from pathlib import Path
ROOT = Path("/media/kafai/NouveauNom/Coran Karim")
CH = ["app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer",
      "app/lib/providers/recitation_provider.dart",
      "app/lib/services/recitation_verifier.dart",
      "app/lib/services/fastconformer_verifier.dart"]

def git(*a):
    return subprocess.run(["git"]+list(a), cwd=ROOT, capture_output=True,
                          text=True, errors="ignore").stdout

commits = [l.split("|") for l in git("log","--all","--date=short",
           "--format=%h|%ad|%s","--",*CH).splitlines() if "|" in l]

RE_CONST = re.compile(r'^([+-])\s*(?:private\s+)?(?:static\s+)?(?:const\s+)?(?:val|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*[:=]')
RE_FUN   = re.compile(r'^([+-])\s*(?:private\s+|internal\s+|suspend\s+|override\s+)*fun\s+([A-Za-z_][A-Za-z0-9_]*)')
RE_DART  = re.compile(r'^([+-])\s*(?:static\s+)?(?:const\s+)?(?:double|int|bool|String|void|Future|List|Map)[<>\w\s,?]*\s+(_?[A-Za-z][A-Za-z0-9_]*)\s*[=(]')

per_commit = {}
const_hist = defaultdict(list)   # constante -> [commits]
fun_hist   = defaultdict(list)   # fonction  -> [commits]

for h, d, s in commits:
    diff = git("show", h, "--unified=0", "--", *CH)
    addC, delC, addF, delF = set(), set(), set(), set()
    for line in diff.splitlines():
        if line.startswith(("+++","---")): continue
        for rx, A, D in ((RE_CONST,addC,delC),(RE_FUN,addF,delF),(RE_DART,addC,delC)):
            m = rx.match(line)
            if m:
                (A if m.group(1)=="+" else D).add(m.group(2))
    per_commit[h] = {"date":d,"sujet":s,"const_add":sorted(addC),"const_del":sorted(delC),
                     "fun_add":sorted(addF),"fun_del":sorted(delF)}
    for c in addC|delC: const_hist[c].append(h)
    for f in addF|delF: fun_hist[f].append(h)

Path("/tmp/gen/audit.json").write_text(json.dumps(
    {"per_commit":per_commit,"const_hist":dict(const_hist),"fun_hist":dict(fun_hist)},
    ensure_ascii=False, indent=1), encoding="utf-8")

nc = sum(len(v["const_add"])+len(v["const_del"]) for v in per_commit.values())
nf = sum(len(v["fun_add"])+len(v["fun_del"]) for v in per_commit.values())
print(f"Commits analyses (diff REEL lu) : {len(per_commit)}")
print(f"Identifiants de constantes touches : {nc}  ({len(const_hist)} distincts)")
print(f"Identifiants de fonctions touches  : {nf}  ({len(fun_hist)} distincts)")
print()
print("=== Les 25 SYMBOLES les plus retouches (= les points chauds) ===")
allh = {**{k:v for k,v in const_hist.items()}, **{k:v for k,v in fun_hist.items()}}
for k, v in sorted(allh.items(), key=lambda x:-len(x[1]))[:25]:
    print(f"  {len(v):2}x  {k}")
