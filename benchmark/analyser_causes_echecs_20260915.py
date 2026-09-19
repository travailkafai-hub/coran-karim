"""Ou la chaine rate-t-elle ? Classe chaque echec par la COUCHE qui en est cause.

Grille : pour chaque mot, on regarde ce que le decodage LIBRE a entendu dans
chaque fenetre, independamment du verdict rendu.
  - mutation RATEE alors qu'une fenetre au moins a entendu autre chose que
    l'attendu  -> l'information existait, la DECISION l'a ecartee ;
  - mutation RATEE sans qu'aucune fenetre n'entende la difference
    -> couche ACOUSTIQUE : le modele ne percoit pas la faute ;
  - FAUX signalement alors que toutes les lectures retenues donnaient
    l'attendu -> DECISION ;
  - FAUX signalement avec des lectures divergentes -> amont (decoupage,
    creneau, fragment de bord).
On ne reinterprete aucune transcription : on compare des cles NFC, comme le vote.
"""
import json, unicodedata
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "benchmark/replay_chaine_jvm_20260915"
MAN = json.loads((ROOT / "benchmark/campagne_paliers_20260915/manifest.json").read_text(encoding="utf-8"))
CAS = {c["case_id"]: c for c in MAN["cases"]}
CONFIG = "vote_t3_bpe"

def cle(t): return unicodedata.normalize("NFC", (t or "").replace("ـ", "").strip())
def signale(s): return s not in ("inconnu", "definitif:VERT", "provisoire:VERT")

rows = {(r["cas"], r["configuration"]): r for r in json.loads((OUT/"resultats.json").read_text(encoding="utf-8"))}

causes_ratees, causes_faux, exclusions = Counter(), Counter(), Counter()
detail_ratees, detail_faux = [], []

for cid, cas in CAS.items():
    row = rows.get((cid, CONFIG))
    log = OUT / f"{cid}_{CONFIG}.log"
    if not row or not log.exists(): continue
    statuts = row["statuts"]
    mots = cas["expected_words"]
    fautes = set()
    for o in cas["operations"]: fautes.update(o["affected_word_indices"])

    obs = {}
    for l in log.read_text(encoding="utf-8", errors="replace").splitlines():
        if "[vote-observation] " not in l: continue
        j = json.loads(l.split("[vote-observation] ", 1)[1])
        obs.setdefault(j["mot"], []).append(j)
        if j.get("exclusion"): exclusions[j["exclusion"]] += 1

    for i, attendu in enumerate(mots):
        s = statuts.get(str(i), "inconnu")
        if s == "inconnu": continue
        lectures = obs.get(i, [])
        utiles = [o for o in lectures if o.get("interieur") and not o.get("sans_creneau") and (o.get("entendu") or "").strip()]
        divergentes = [o for o in utiles if cle(o.get("entendu")) != cle(attendu)]
        if i in fautes and not signale(s):
            if divergentes:
                causes_ratees["DECISION : la difference a ete entendue, le verdict l'a ecartee"] += 1
                detail_ratees.append((cid, i, attendu, [o.get("entendu") for o in divergentes][:3], s))
            elif utiles:
                causes_ratees["ACOUSTIQUE : toutes les lectures donnent le mot attendu"] += 1
            else:
                causes_ratees["AMONT : aucune lecture utilisable (bord, creneau, vide)"] += 1
        elif i not in fautes and signale(s):
            if not divergentes and utiles:
                causes_faux["DECISION : toutes les lectures donnaient l'attendu"] += 1
                detail_faux.append((cid, i, attendu, [round(o.get("gop") or 0, 2) for o in utiles][:3], s))
            elif divergentes:
                causes_faux["AMONT : le decodage libre a lu autre chose"] += 1
                detail_faux.append((cid, i, attendu, [o.get("entendu") for o in divergentes][:3], s))
            else:
                causes_faux["AMONT : aucune lecture utilisable"] += 1

print("=== MUTATIONS RATEES : ou est la cause ? ===")
for k, v in causes_ratees.most_common(): print(f"  {v:4d}  {k}")
print("\n=== FAUX SIGNALEMENTS : ou est la cause ? ===")
for k, v in causes_faux.most_common(): print(f"  {v:4d}  {k}")
print("\n=== observations ECARTEES, par raison ===")
for k, v in exclusions.most_common(8): print(f"  {v:5d}  {k}")
print("\n=== exemples de mutations ratees alors qu'ELLES ONT ETE ENTENDUES ===")
for d in detail_ratees[:8]: print(f"  {d[0]}/{d[1]:<4} attendu={d[2]:<16} entendu={d[3]} -> {d[4]}")
print("\n=== exemples de faux signalements ===")
for d in detail_faux[:8]: print(f"  {d[0]}/{d[1]:<4} attendu={d[2]:<16} {d[3]} -> {d[4]}")
