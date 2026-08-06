#!/usr/bin/env python3
"""Consigne la regle d'AVANCE (2026-08-06) : a egalite, l'ancre avance.

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
    ("regle_a_egalite_avancer_plutot_que_reculer",
     "[REGLE] A egalite parfaite, l'alignement qui AVANCE gagne",
     "MESURE QUI L'IMPOSE (2026-08-06, sourate 94 Ash-Sharh, session live, "
     "build v78). Versets 5 et 6 identiques a une lettre pres : 17-20 "
     "`فَإِنَّ مَعَ ٱلْعُسْرِ يُسْرًا`, 21-24 `إِنَّ مَعَ ٱلْعُسْرِ يُسْرًا`. Le mot "
     "distinctif aurait du trancher -- `فان` et `ان` ne s'apparient PAS entre "
     "eux (prefixe < 3 lettres, distance d'edition non applicable sous 5). "
     "Mais le modele l'a lu `إِنَّمَا` (dans le log : `entendu=\"إِنَّمَا\"`), qui "
     "ne correspond ni a l'un ni a l'autre. Il ne restait que `مع العسر يسرا` "
     ": TROIS mots communs aux deux copies, meme longueur de chaine, meme "
     "portee -- EGALITE PARFAITE. L'ancien departage (« index le plus petit ») "
     "choisissait la premiere copie : `f=21/23/25 RECUL vers le mot 18`. "
     "L'ancre n'a jamais traverse le verset 6 ; au verset 7 la chaine l'a bien "
     "vu (`attestes=[25, 26, 27]`) mais l'ecart 20->25 valait 4 mots -> quatre "
     "SAUT REFUSE puis DECROCHAGE, ancre bloquee a 20 sur 31 jusqu'a la fin. "
     "LA REGLE, validee par l'utilisateur : continuer est le cas NORMAL, "
     "repeter est un EVENEMENT. A qualite strictement egale l'alignement qui "
     "avance gagne ; un recul doit etre justifie par une chaine PLUS LONGUE, "
     "qui reste prioritaire. Ordre : longueur, puis avance, puis compacite, "
     "puis plus petit index. "
     "RESULTAT (rejeu deterministe Al-Baqara, meme audio au bit pres) : "
     "3/295 = 1,02 % -> 2/295 = 0,68 %, 0 SAUT REFUSE, ancre 294. Le mot 228 "
     "`وَإِن`, declare `omis` depuis des jours alors que son texte etait lu "
     "EXACTEMENT, disparait : c'etait la meme ambiguite resolue vers "
     "l'arriere. PREUVE : LocalisateurTest, 5 tests, celui-ci ECHOUE sans la "
     "regle."),

    ("piege_test_jouet_qui_ne_reproduit_pas_le_cas",
     "[PIEGE] Un test qui passe AVANT le correctif ne prouve rien",
     "MESURE (2026-08-06) : premier test ecrit pour la sourate 94, il passait "
     "avec ET sans le correctif -- la contrainte temporelle suffisait deja a "
     "trancher le cas JOUET, qui n'etait donc pas le cas reel. Verifie en "
     "remisant le fichier (`git stash`) avant de conclure quoi que ce soit. "
     "DEUXIEME PIEGE du meme jour, dans le meme test : le decodeur synthetique "
     "replie deux tokens identiques consecutifs (comportement CTC), `inna` "
     "ressortait `ina` et ne s'appariait plus a lui-meme -- les mots jouets ne "
     "doivent porter AUCUNE lettre doublee. REGLE : tout test de non-"
     "regression se valide en verifiant qu'il ECHOUE sans le correctif."),

    ("mesure_departage_par_compacite",
     "[MESURE] Departage par compacite : correct mais insuffisant seul",
     "A longueur egale, preferer la chaine de plus petite portee revient a "
     "retenir l'explication qui suppose le MOINS de mots non prononces. Pose "
     "en meme temps que la regle d'avance et conserve, mais MESURE INSUFFISANT "
     "SEUL sur le cas de la sourate 94 : les deux alignements y ont la meme "
     "portee (3 mots contigus de part et d'autre), la compacite ne les separe "
     "pas. Il faut la regle d'avance. Garde parce qu'il est fonde et qu'il "
     "tranche les cas de portees inegales, pas parce qu'il a produit un gain "
     "isole."),
]

LIENS = [
    ("regle_a_egalite_avancer_plutot_que_reculer",
     "regle_contrainte_temporelle_appariement", "complete"),
    ("mesure_departage_par_compacite",
     "regle_a_egalite_avancer_plutot_que_reculer", "insuffisant_sans"),
    ("piege_test_jouet_qui_ne_reproduit_pas_le_cas",
     "regle_a_egalite_avancer_plutot_que_reculer", "meme_session"),
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
        shutil.copy2(GRAPHE, SORTIE / "graph_avant_avance.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")
    print("sauvegarde de l'etat precedent : graphify-out/graph_avant_avance.json")


if __name__ == "__main__":
    main()
