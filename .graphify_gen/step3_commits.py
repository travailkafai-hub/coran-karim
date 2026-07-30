# -*- coding: utf-8 -*-
"""Etape 3 : commits, branches, versions, et surtout LE COUPLAGE entre commits.
Deux commits sont couples s'ils touchent le meme fichier ou la meme constante -
c'est CE couplage, invisible dans les messages, qui produit les regressions."""
import json, re, subprocess, itertools
from collections import defaultdict
from pathlib import Path

ROOT = Path("/media/kafai/NouveauNom/Coran Karim")
SRC = str(ROOT/"graphify-out/git_history_all_branches.md")
st = json.loads(Path("/tmp/gen/state2.json").read_text(encoding="utf-8"))
nodes, edges, hyper = st["nodes"], st["edges"], st["hyperedges"]
seen = {n["id"] for n in nodes}

def N(i,l,t,s,loc=None,**x):
    if i in seen: return i
    seen.add(i); d={"id":i,"label":l,"file_type":t,"source_file":s,"source_location":loc,
    "source_url":None,"captured_at":None,"author":None,"contributor":None}; d.update(x); nodes.append(d); return i
def E(s,t,r,c,sc,sf,loc=None,w=1.0):
    if s in seen and t in seen:
        edges.append({"source":s,"target":t,"relation":r,"confidence":c,"confidence_score":sc,
                      "source_file":sf,"source_location":loc,"weight":w})
def H(i,l,ns,r,c,sc,s):
    ns=[n for n in ns if n in seen]
    if len(ns)>=3: hyper.append({"id":i,"label":l,"nodes":ns,"relation":r,"confidence":c,"confidence_score":sc,"source_file":s})

def git(*a):
    return subprocess.run(["git"]+list(a), cwd=ROOT, capture_output=True, text=True).stdout

# ---- branches
BRANCHES = ["master","asr-nemo-solutions","chunkwise-aligner","gradient-aligner","test-1-gop","test-2-gop"]
for b in BRANCHES:
    N(f"branche_{re.sub(r'[^a-z0-9]+','_',b)}", f"branche {b}", "concept", SRC,
      rationale=f"Branche git {b}")

# ---- commits (toutes branches)
raw = git("log","--all","--date=short","--format=%h\x01%ad\x01%s\x01%D")
commits = {}
for line in raw.splitlines():
    p = line.split("\x01")
    if len(p) < 3: continue
    h, d, s = p[0], p[1], p[2]
    deco = p[3] if len(p)>3 else ""
    cid = f"commit_{h}"
    N(cid, f"{d} {s[:95]}", "document", SRC, rationale=s)
    commits[h] = (d, s, deco)
    for b in BRANCHES:
        if b in deco:
            E(f"branche_{re.sub(r'[^a-z0-9]+','_',b)}", cid, "references","EXTRACTED",1.0,SRC)

# ---- chaine chronologique (parent -> enfant) : l'ordre reel du travail
order = [h for h in commits]
for a, b in zip(order, order[1:]):
    E(f"commit_{b}", f"commit_{a}", "references", "EXTRACTED", 1.0, SRC)

# ---- COUPLAGE PAR FICHIER : quels commits touchent le meme fichier ?
CIBLES = [
 "app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",
 "app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/ForcedAligner.kt",
 "app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/RescueBuffer.kt",
 "app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/FastConformerCtc.kt",
 "app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/MelSpectrogram.kt",
 "app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/FastConformerCtcPlugin.kt",
 "app/lib/providers/recitation_provider.dart",
 "app/lib/services/recitation_verifier.dart",
]
fichier_commits = {}
for f in CIBLES:
    fid = "fichier_" + re.sub(r'[^a-z0-9]+','_', Path(f).name.lower())
    N(fid, Path(f).name, "code", f, rationale=f"Fichier du chemin critique : {f}")
    hs = [l for l in git("log","--all","--format=%h","--",f).splitlines() if l]
    fichier_commits[fid] = hs
    for h in hs:
        E(f"commit_{h}", fid, "references", "EXTRACTED", 1.0, SRC)

# ---- COUPLAGE PAR CONSTANTE : le lien invisible entre commits
CONSTS = ["RESYNC_ACTIF","CHUNKWISE_ACTIF","MAX_SILENCE_SAMPLES","MAX_SEGMENT_SECONDS",
 "RIGHT_CONTEXT_SECONDS","OVERLAP_SECONDS","RESCUE_RING_SECONDS","CUT_SEARCH_RADIUS_SECONDS",
 "MIN_FRAMES_FOR_JUDGMENT","SILENCE_RMS_THRESHOLD","DEFAULT_COMMIT_SILENCE_MS","MIN_NEW_SECONDS",
 "MIN_COMMIT_SECONDS","MAX_ALIGN_WORDS","RESCUE_CONTEXT_SECONDS","MIN_RESYNC_HITS",
 "MAX_RESYNC_LOOKAHEAD","SHIFTED_OFFSET_SECONDS","_kGopCorrectDefault","_kGopUnclearDefault",
 "_kFreeConfidentTolerant","MAX_SECONDS","TARGET_SECONDS","MIN_TARGET_SECONDS"]
ncoup = 0
for c in CONSTS:
    vid = f"var_{c.lower().lstrip('_')}"
    if vid not in seen: continue
    hs = [l for l in git("log","--all","--format=%h","-S",c).splitlines() if l]
    for h in hs:
        E(f"commit_{h}", vid, "shares_data_with", "EXTRACTED", 1.0, SRC)
    # deux commits qui touchent la MEME constante sont couples, meme sans le dire
    for a, b in itertools.combinations(hs[:9], 2):
        E(f"commit_{a}", f"commit_{b}", "semantically_similar_to", "INFERRED", 0.95, SRC,
          loc=f"couples par {c}")
        ncoup += 1
    if len(hs) >= 3:
        H(f"hyper_touche_{c.lower().lstrip('_')}", f"Commits touchant {c}",
          [f"commit_{h}" for h in hs[:12]], "participate_in", "EXTRACTED", 1.0, SRC)

print(f"[3/6] Commits : {len(commits)} | couplages inter-commits par constante : {ncoup}")
print(f"      Total : {len(nodes)} noeuds, {len(edges)} aretes, {len(hyper)} hyperaretes")
Path("/tmp/gen/state3.json").write_text(json.dumps(
    {"nodes":nodes,"edges":edges,"hyperedges":hyper}, ensure_ascii=False), encoding="utf-8")
