#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Promouvoir au vert quand le transcrit est parfait : ce que la mesure dit."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_894_verdicts_au_transcrit_identique",
     "[MESURE] 894 verdicts ont un transcrit STRICTEMENT identique a l'attendu -- dont 22 `deplace`",
     "Mesure du 2026-09-05 sur l'ensemble des journaux device disponibles, "
     "faite pour instruire la proposition utilisateur « comme le texte etait "
     "bien transcrit, on pourrait rajouter une fonction qui ameliore le "
     "verdict au vert quand le transcrit est ok ». Repartition des 894 : "
     "810 vert, 53 rouge, 22 DEPLACE, 9 orange. "
     "LE CHIFFRE QUI TRANCHE : 22 mots `deplace` ont un transcrit parfait. "
     "Une promotion fondee sur le seul transcrit les validerait tous -- un mot "
     "dit ailleurs, ou pas dit du tout et pose par la DP sur l'audio du voisin "
     "(cf. le [PIEGE] deja au graphe). `entendu` est le decodage LIBRE sur les "
     "frames attribuees au mot : quand l'attribution est fausse, le transcrit "
     "est bon sans que le mot ait ete prononce -- et le texte coranique se "
     "repete. "
     "PARMI LES 62 NON-VERTS au transcrit identique : 37 ont une marge de "
     "lettres POSITIVE (jusqu'a +10,4 sur `لَّهُۥ`), 25 l'ont negative. Les "
     "exemples des 37 portent tous un caractere de la liste perdue par "
     "`word_tokens.json` -- `لَّهُۥ` porte U+06E5 (381 mots), `ءَامَنُوا۟` et "
     "`وَتَوَاصَوْا۟` portent U+06DF (1 259 mots). Ce ne sont donc pas des cas a "
     "pardonner : ce sont les victimes du defaut corrige par le filtre des "
     "entrees amputees."),

    ("en_attente_promotion_au_vert_bornee_par_la_marge",
     "[EN ATTENTE] Promouvoir au vert un mot au transcrit parfait, SEULEMENT si la marge de lettres est positive",
     "Proposition utilisateur du 2026-09-05, NON IMPLEMENTEE, et deliberement. "
     "DEUX RAISONS DE NE PAS LA FAIRE MAINTENANT. (1) Ce serait empiler un "
     "correctif sur un correctif non encore mesure : le filtre des entrees "
     "amputees vient d'etre pose et devrait faire disparaitre l'essentiel des "
     "37 cas -- si c'est le cas, la fonction n'a plus d'objet. (2) Elle "
     "eteindrait le SIGNAL qui a permis de trouver la cause : sans ces rouges "
     "au transcrit parfait, le defaut de tokenisation serait reste invisible. "
     "C'est exactement ce que dit la regle du projet -- une tolerance en aval "
     "« rend le vrai defaut invisible dans les logs suivants ». "
     "LA FORME DEFENDABLE, si des faux rouges subsistent APRES mesure : "
     "promouvoir uniquement quand `margeLettres >= 0`, de sorte que la marge "
     "garde son veto (les confusions et les mots deplaces restent rouges), et "
     "JOURNALISER chaque promotion pour qu'un defaut d'alignement reste "
     "lisible au lieu d'etre avale. Sous cette forme ce n'est plus une "
     "tolerance : on n'abaisse aucun critere, on constate que deux preuves "
     "acoustiques independantes (decodage libre exact ET preference sur toutes "
     "les confusions) contredisent un score de chemin contraint."),
]

LIENS = [
    ("en_attente_promotion_au_vert_bornee_par_la_marge",
     "mesure_894_verdicts_au_transcrit_identique", "shares_data_with",
     "la proposition et la mesure qui borne sa forme"),
    ("mesure_894_verdicts_au_transcrit_identique",
     "mesure_word_tokens_ampute_un_mot_sur_sept", "shares_data_with",
     "les faux rouges au transcrit parfait portent les caracteres perdus"),
    ("en_attente_promotion_au_vert_bornee_par_la_marge",
     "regle_un_transcrit_identique_ne_prouve_pas_un_forced_correct",
     "shares_data_with",
     "pourquoi le transcrit seul ne peut pas porter un verdict"),
]


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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step45.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print("+{} noeuds, +{} aretes -> {} noeuds, {} aretes".format(
        a, ar, len(g["nodes"]), len(g["links"])))


if __name__ == "__main__":
    main()
