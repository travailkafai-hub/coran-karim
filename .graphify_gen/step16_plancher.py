#!/usr/bin/env python3
"""Consigne la mesure du PLANCHER DE DUREE (2026-08-06) : hypothese refutee.

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
    ("mort_plancher_de_duree_fonde_sur_les_lettres",
     "[MORT] Plancher de duree de l'aligneur fonde sur les lettres (ou le madd)",
     "IDEE (utilisateur, 2026-08-06) : « l'alignement connait la taille du mot, "
     "il ne teste pas la taille attendue » puis « avec le tajwid encore, il va "
     "prolonger ». Le constat est JUSTE -- `AligneurForce.framesMinimales` "
     "derive le plancher du NOMBRE DE JETONS, propriete du vocabulaire et non "
     "de la parole (184 mots sur 19 001 valent un seul jeton). "
     "MESURE QUI TUE LE CORRECTIF, faite AVANT de l'ecrire, sur 906 "
     "observations de mots juges CORRECTS (4 sessions deterministes "
     "Al-Baqara) : a CHAQUE longueur de mot (2 a 6 lettres) le minimum de "
     "frames vaut 1, et le 5e centile vaut 1 ou 2 ; rapport frames/lettre : "
     "1er centile 0,20, 5e 0,33, mediane 1,00. Le CTC est « pique » -- il emet "
     "un jeton sur une frame et met du blanc autour. Un plancher fonde sur les "
     "lettres, meme tres permissif, exclurait une part importante de mots "
     "corrects. `frames=1` n'est donc PAS une anomalie en soi."),

    ("piege_cible_impose_une_piece_que_le_modele_n_emet_pas",
     "[PIEGE] La cible force une piece entiere que le modele n'a pas produite",
     "MESURE (2026-08-06, cas reel Al-Baqara mot 42 `كَفَرُوا۟` : "
     "`definitif:rouge gop=-5.33 forced=-5.34 free=-0.01 frames=1 obs=4 "
     "entendu=\"كَفَ\"`, alors que le flux brut le porte ENTIER et lisible aux "
     "largeurs 4 s et 6 s, et qu'une fenetre de 11,76 s l'avait au centre avec "
     "11/11 mots interieurs). "
     "REPRODUIT AU BANC (PlancherDureeTest, 30 s, sans telephone), deux "
     "mesures symetriques : audio ou le modele EMET la piece entiere + cible "
     "en piece entiere -> 8 frames, gop=0,00 ; audio ou le modele EPELLE + "
     "cible en piece entiere -> 1 frame, gop=-11,99, entendu reduit a un "
     "fragment. La signature du device est reproduite exactement. "
     "CE QUE CA ETABLIT : le discriminant n'est pas la duree (un mot correct a "
     "lui aussi frames=1) mais l'ACCORD entre la cible et ce que le modele "
     "produit sur CET audio. `entendu` etant le decodage libre RESTREINT aux "
     "frames attribuees au mot, un desaccord de granularite le reduit "
     "mecaniquement a un fragment. "
     "CORRECTIF NON ECRIT : laisser l'aligneur CHOISIR entre la piece entiere "
     "et l'epellation -- les deux echecs sont symetriques, choisir un camp "
     "serait faux dans l'autre sens. Touche le treillis CTC lui-meme."),
]

LIENS = [
    ("mort_plancher_de_duree_fonde_sur_les_lettres",
     "piege_cible_impose_une_piece_que_le_modele_n_emet_pas", "remplace_par"),
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
        shutil.copy2(GRAPHE, SORTIE / "graph_avant_plancher.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")
    print("sauvegarde de l'etat precedent : graphify-out/graph_avant_plancher.json")


if __name__ == "__main__":
    main()
