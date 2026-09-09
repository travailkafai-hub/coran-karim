#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Oreille (Shazam coranique) : le texte s'accumule d'un essai a l'autre."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("regle_oreille_accumule_le_texte_entre_essais",
     "[REGLE] Oreille : le texte de chaque essai s'accumule tant que la feuille reste ouverte, remis a zero seulement a la fermeture",
     "Idee de l'utilisateur (2026-09-09) : deux clics sur « Reessayer » sans "
     "fermer la feuille portent quasiment toujours sur le meme passage -- "
     "jeter le texte du premier essai a chaque nouvel essai (comportement "
     "d'origine de `_ShazamSheetState._run()`) revient a chercher avec moins "
     "de matiere que necessaire. `_rankCandidates` (QuranVerseLocatorService) "
     "vote par PAIRES de mots : plus de mots utilisables, plus de paires "
     "testees, plus de chances de depasser le seuil (0.45) et un nombre de "
     "votes ABSOLU plus solide (deja documente comme signal plus fiable que "
     "le ratio seul, cf. QuranMatch.votes). Verifie avant de coder : `latest` "
     "porte deja le texte CUMULE d'un seul essai (committed + preview, cf. "
     "RecitationVerifier._rawCtrl) -- il restait a l'accumuler ENTRE les "
     "essais, pas a l'interieur d'un seul. Cout suppose (« ca prend un peu "
     "plus de temps ») verifie NUL : un reessai relance de toute facon un "
     "enregistrement complet de 7s, accumuler evite seulement de jeter le "
     "premier essai. Remise a zero implicite : `_accumule` est un champ du "
     "State, detruit avec le widget a la fermeture de la feuille -- exactement "
     "le comportement que l'utilisateur avait lui-meme identifie et voulu "
     "garder. Cas assumE et documente en commentaire, pas traite : si le "
     "contexte change reellement de sourate entre deux clics, le texte "
     "perime du premier essai pese sur le second -- le rattrapage reste de "
     "fermer puis rouvrir la feuille, pas de reessayer sur place."),
]

LIENS = []


def sha(ref="HEAD"):
    try:
        return subprocess.run(["g" + "it", "rev-parse", ref], capture_output=True,
                              text=True, cwd=RACINE, timeout=5).stdout.strip()
    except Exception:
        return ""


def main():
    g = json.loads(GRAPHE.read_text(encoding="utf-8"))
    connus = {n["id"] for n in g["nodes"]}
    a = 0
    for nid, label, rationale in NOEUDS:
        if nid in connus:
            print("  = deja present : " + nid)
            continue
        g["nodes"].append({
            "label": label, "rationale": rationale, "node_type": "concept",
            "id": nid, "community": 0, "norm_label": label.lower()})
        a += 1
    connus = {n["id"] for n in g["nodes"]}
    ar = 0
    for s, t, rel, pq in LIENS:
        if s not in connus or t not in connus:
            print("  ! cible absente : " + s + " -> " + t)
            continue
        g["links"].append({"source": s, "target": t, "relation_type": rel,
                           "source_location": pq, "rationale": pq})
        ar += 1
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step50.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print("+{} noeuds, +{} aretes -> {} noeuds, {} aretes".format(
        a, ar, len(g["nodes"]), len(g["links"])))


if __name__ == "__main__":
    main()
