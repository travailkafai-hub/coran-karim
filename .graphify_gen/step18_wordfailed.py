#!/usr/bin/env python3
"""Consigne le signal wordFailed jamais emis par la v2 (2026-08-06), et la
troisieme refutation sur les ecritures.

Meme principe que step10_decrochage.py : on enrichit, on n'ecrase pas, et
le `rationale` porte LE CHIFFRE ou LA LIGNE DE LOG -- jamais l'intention.

Contexte : une soiree entiere de correctifs sur le decrochage / SAUT REFUSE,
dont la moitie visaient le mauvais maillon. Ce fichier existe pour qu'on ne
repaye pas ces heures -- chaque noeud dit ce qui a ETE MESURE, pas ce qui a ete
espere.

Protocole des mesures : sessions reelles sur device (Samsung R3CY20XW7TD),
builds v49 a v57, sourates 90/93/95, mode NORMALE sauf mention, journal
`recitation_diagnostic.log` + flux brut `stream_*.wav` confronte au modele.
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("piege_wordfailed_jamais_emis_par_la_v2",
     "[PIEGE] La correction automatique ne pouvait PAS se declencher en v2",
     "MESURE (2026-08-06, session utilisateur An-Nisa' 1-4, build v85, "
     "`correction=active`) : DEUX mots `definitif:rouge` et `wordFailed` = 0 "
     "occurrence sur toute la session. "
     "CAUSE, lue dans le code : `_wordFailedCtrl.add(i)` n'existe qu'a quatre "
     "endroits, TOUS dans `_onAligned` -- la chaine v1, prouvee morte par "
     "l'instrumentation `[V1]` (1 seule ligne sur une session entiere). "
     "`_onV2`, qui applique reellement les verdicts, appelait `_judge` SANS "
     "lui passer `newErrors` : rien n'etait collecte, rien n'etait emis. Un "
     "commentaire disait meme « aucun risque de declencher la correction "
     "automatique au passage [...] et `_onV2` n'en passe pas » -- l'intention "
     "(ne pas corriger sur un negatif PROVISOIRE) etait juste, l'effet etait "
     "total. "
     "PORTEE : depuis que la v2 pilote l'ecran, la correction automatique "
     "n'existait plus. Tous les reglages de ses CONDITIONS (deux mots "
     "consecutifs, minuteur de silence, respect du reglage) portaient sur une "
     "branche que rien n'atteignait -- plusieurs seances de travail sur du code "
     "mort. Seul le DECROCHAGE fonctionnait, parce qu'il passe par un autre "
     "flux (`decrochage`). "
     "REGLE GENERALE : quand un mecanisme ne se declenche jamais, verifier "
     "d'abord QUI EMET son signal, pas dans quelles conditions il se "
     "declenche."),

    ("mort_rattrapage_ecritures_par_moyenne_sur_plage_elargie",
     "[MORT] Rescorer un mot condamne sur une plage elargie, en moyenne",
     "TROISIEME tentative sur le mot dont la cible impose une piece que le "
     "modele n'emet pas, et TROISIEME refutation. Forme bornee (idee de "
     "l'utilisateur) : ne pas toucher a l'alignement global, rescorer le SEUL "
     "mot condamne sur l'audio libre entre ses deux voisins, avec le graphe de "
     "toutes ses ecritures, et garder le maximum. "
     "MESURE : 0,68 % -> 6,12 % de mots non verts sur le meme WAV Al-Baqara. "
     "POURQUOI, et c'est une erreur de conception : le score est une MOYENNE "
     "PAR FRAME. Elargir la plage y ajoute des frames de silence, dont la "
     "probabilite de blanc est elevee -- la moyenne monte artificiellement, le "
     "rescoring gagne presque partout et remplace de bons alignements par des "
     "plages larges vides de sens. Comparer une moyenne sur 1 frame a une "
     "moyenne sur 12 n'est pas une comparaison. "
     "CE QU'IL FAUDRAIT POUR REESSAYER : un score COMPARABLE entre deux plages "
     "de longueurs differentes (par exemple le score total du seul chemin des "
     "jetons, silences exclus) et non une moyenne. Tant que ce point n'est pas "
     "resolu, ne pas rebrancher."),
]

LIENS = [
    ("mort_rattrapage_ecritures_par_moyenne_sur_plage_elargie",
     "mort_alignement_sur_toutes_les_ecritures_de_la_bande", "meme_sujet"),
    ("piege_wordfailed_jamais_emis_par_la_v2",
     "regle_le_blocage_suit_le_reglage_pas_une_heuristique", "invalidait"),
]

CORRECTIONS = {}


def noeud(nid, label, rationale):
    return {"id": nid, "label": label, "rationale": rationale,
            "node_type": "concept", "community": "recitation"}


def sha() -> str:
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=RACINE,
                          capture_output=True, text=True).stdout.strip()


def main():
    g = json.loads(GRAPHE.read_text(encoding="utf-8"))
    connus = {n["id"] for n in g["nodes"]}
    ajoutes = 0
    for nid, label, rationale in NOEUDS:
        if nid not in connus:
            g["nodes"].append(noeud(nid, label, rationale))
            ajoutes += 1
        else:
            # On ENRICHIT sans ecraser : si le noeud existe deja, on ne touche
            # a rien (regle projet -- aucune piste n'est jamais ecrasee).
            print(f"  = deja present, inchange : {nid}")

    corriges = 0
    for n in g["nodes"]:
        if n["id"] in CORRECTIONS:
            n["rationale"] = CORRECTIONS[n["id"]]
            corriges += 1
            print(f"  ~ rationale CORRIGE (mesure invalide) : {n['id']}")
    print(f"  {corriges} noeud(s) corrige(s)")

    connus = {n["id"] for n in g["nodes"]}
    aretes = 0
    for s, t, rel in LIENS:
        if s not in connus or t not in connus:
            print(f"  ! cible absente, arete ignoree : {s} -> {t}")
            continue
        g["links"].append({
            "source": s, "target": t, "relation_type": rel,
            "source_location": None, "rationale": None,
        })
        aretes += 1

    if GRAPHE.exists():
        shutil.copy2(GRAPHE, SORTIE / "graph_avant_wordfailed.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")
    print("sauvegarde de l'etat precedent : graphify-out/graph_avant_wordfailed.json")


if __name__ == "__main__":
    main()
