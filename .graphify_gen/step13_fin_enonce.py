#!/usr/bin/env python3
"""Consigne la regle de FIN D'ENONCE (2026-08-06) : le silence ferme le bloc.

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
    ("regle_fin_enonce_le_silence_ferme_le_bloc",
     "[REGLE] Un silence long ferme le bloc lui-meme, sans attendre la reprise",
     "IDEE UTILISATEUR (2026-08-06) : « quand je finis la sourate apres il y a "
     "un silence long, je ne sais pas comment l'exploiter pour valider la fin "
     "de la recitation ». DEFAUT QU'ELLE CORRIGE : la coupe n'etait armee que "
     "dans la branche « la parole REPREND » de ConstructeurDeFenetres. A la fin "
     "d'une sourate la parole ne reprend jamais -> le dernier bloc n'etait "
     "JAMAIS ferme, ses derniers mots n'etaient vus que par des apercus, donc "
     "au bord droit, donc non votants. Mesure, trois recitations reelles : "
     "Al-Ma'un 5 mots de fin jamais atteints, Al-Humaza 3, Ad-Duha 5, avec "
     "`f=26 bande=33..34 interieurs=0/2` et `f=29 bande=36..41 interieurs=4/6` "
     "-- la fenetre VOIT les mots sans pouvoir les juger. "
     "SEUIL 3 s, MESURE ET NON CHOISI : distribution des silences sur les trois "
     "sessions utilisateur plus la recette Al-Baqara (96 pauses, queue exclue) "
     "-- mediane 0,6 a 1,0 s, 90e centile 2,6 s, SIX pauses seulement au-dela "
     "de 3 s et toutes des arrets reels ; les silences de fin mesurent 6,6 / "
     "7,6 / 12,9 s. "
     "RESULTAT (rejeu deterministe du WAV d'Ad-Duha de l'utilisateur) : ancre "
     "39/40, ZERO mot de fin jamais atteint (contre 5), 2,5 % de non verts "
     "contre 25,0 %. Non-regression Al-Baqara : 3/295 = 1,02 %, memes trois "
     "mots, 0 RESYNC, 0 verdict sans preuve. "
     "POURQUOI CE N'EST PAS UN CRITERE D'ACCEPTATION DEPLACE : se tromper de "
     "seuil n'enleve aucune observation, n'avance aucune ancre et ne fige aucun "
     "verdict -- ca AJOUTE une fenetre la ou il n'y en avait aucune. Et ca "
     "n'arrete NI la capture NI la session : le recitateur qui marque une pause "
     "de reflexion, ou qui enchaine la sourate suivante, n'est pas interrompu."),
]

LIENS = [
    ("regle_fin_enonce_le_silence_ferme_le_bloc",
     "piege_session_jamais_fermee_fin_de_recitation", "corrige"),
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
        shutil.copy2(GRAPHE, SORTIE / "graph_avant_fin_enonce.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")
    print("sauvegarde de l'etat precedent : graphify-out/graph_avant_fin_enonce.json")


if __name__ == "__main__":
    main()
