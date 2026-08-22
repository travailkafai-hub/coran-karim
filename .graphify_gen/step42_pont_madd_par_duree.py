#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Le pont des madd : quatre statuts juridiques contre deux durees."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("regle_pont_madd_statut_vers_duree",
     "[REGLE] Le pont des madd se fait par la DUREE, et `madda_permissible` accepte LES DEUX",
     "Le texte annote nomme les madd par leur STATUT juridique "
     "(madda_necessary/obligatory/permissible/normal), le modele a 17 classes "
     "par leur DUREE (madd_long, madd_court). Sans traduction, AUCUNE regle de "
     "madd ne peut jamais etre satisfaite : l'app cherche un nom que le modele "
     "ne produit jamais, et tout madd correct serait signale. Correspondance "
     "retenue, deduite par l'utilisateur et confirmee par la legende du mushaf "
     "relevee dans modele_4tetes_2026-08-21/docs/ ainsi que par les temps deja "
     "documentes dans tajweed_text.dart : madda_normal (2 temps) -> "
     "madd_court ; madda_obligatory (4-5 temps) et madda_necessary (6 temps, "
     "lazim) -> madd_long. POINT CENTRAL : madda_permissible est ecrit "
     "`مدّ 2 أو 4 أو 6 جوازاً` -- la duree est au CHOIX du recitant, donc les "
     "DEUX realisations sont licites et le pont accepte l'une OU l'autre. "
     "Trancher arbitrairement aurait invente des fautes sur 4 543 occurrences, "
     "pres d'un madd sur quatre. Le pont ne peut que RETIRER une fausse alerte, "
     "jamais en creer : il n'ajoute que des facons de satisfaire une regle."),

    ("mesure_les_deux_madd_se_recouvrent_en_duree",
     "[MESURE] `madd_long` et `madd_court` se RECOUVRENT en duree -- l'explication probable des 50 % d'invention",
     "Durees relevees dans un journal device reel (tete 2, session Al-Fatiha "
     "Warsh du 2026-08-22) : madd_court s'etale de 1 360 a 2 560 ms, madd_long "
     "de 1 760 a 3 120 ms. La zone 1 760-2 560 ms appartient AUX DEUX. Le "
     "modele doit donc trancher une frontiere de duree floue -- ce qui est "
     "coherent avec les 50,4 % d'invention de madd_long mesures a "
     "l'entrainement et avec l'explication qui y est donnee (« c'est une regle "
     "de DUREE, pas de timbre »). ⚠️ Ces plages viennent d'UNE session et "
     "melangent tous les mots : elles bornent un ordre de grandeur, elles ne "
     "sont pas une calibration."),

    ("en_attente_juger_le_madd_par_sa_duree_mesuree",
     "[EN ATTENTE] Juger le madd par sa DUREE MESUREE plutot que par la classe emise",
     "Piste ouverte par l'utilisateur le 2026-08-22 (« le madd 2 6... », « tu "
     "peux en deduire une regle alors »). La tete 2 journalise deja une duree "
     "en ms par regle et par mot (`[tajwidDuree] mot=N madd_long=26f(2080ms)`). "
     "Si la duree d'un temps (haraka) etait connue pour le recitateur courant, "
     "on pourrait deduire 2 / 4 / 6 temps DIRECTEMENT de la mesure, au lieu de "
     "faire confiance a une classe qui invente une fois sur deux. Cela "
     "attaquerait la cause (une frontiere de duree floue) au lieu du symptome. "
     "Le projet a deja de quoi estimer cette unite : `WordDurationStore` "
     "(durees apprises par mot, voix de l'utilisateur) et `PauseProfile` "
     "(profil de pauses personnel par passage). NON IMPLEMENTE : ce serait une "
     "nouvelle regle de JUGEMENT, elle doit etre mesuree avant d'etre ecrite "
     "-- notamment le fait que la duree d'un temps varie avec le tempo du "
     "recitateur, ce qui est precisement ce qu'un profil personnel sait "
     "capter."),

    ("piege_ajouter_a_un_enum_parcouru_par_values",
     "[PIEGE] Ajouter une valeur a `TajwidRule` la fait apparaitre dans l'IHM sans qu'on le demande",
     "En ajoutant maddLong/maddCourt a l'enum (pour que la sortie du modele "
     "soit traduisible telle quelle), deux endroits parcouraient "
     "`TajwidRule.values` : l'ecran de selection des regles "
     "(tajwid_rules_screen.dart) aurait affiche deux entrees qu'AUCUN mot ne "
     "porte jamais -- le texte annote ne les produit pas -- et les activer "
     "n'aurait eu aucun effet. Corrige par une liste explicite "
     "`TajwidRule.selectionnables` (les 17 regles que le texte annote peut "
     "attendre), l'IHM et les presets passant desormais par elle. `fromKey` "
     "reste sur `values` : c'est une recherche par NOM, elle doit voir toutes "
     "les valeurs. REGLE : un enum qui sert A LA FOIS de vocabulaire de sortie "
     "d'un modele et de liste de choix utilisateur a besoin des deux listes."),
]

LIENS = [
    ("regle_pont_madd_statut_vers_duree",
     "mesure_madd_long_invente_une_fois_sur_deux", "shares_data_with",
     "le pont est pose, mais l'une des deux classes reste peu fiable"),
    ("mesure_les_deux_madd_se_recouvrent_en_duree",
     "mesure_madd_long_invente_une_fois_sur_deux", "shares_data_with",
     "la mesure device explique le chiffre de l'entrainement"),
    ("en_attente_juger_le_madd_par_sa_duree_mesuree",
     "mesure_les_deux_madd_se_recouvrent_en_duree", "shares_data_with",
     "le recouvrement est la raison pour laquelle mesurer vaudrait mieux que classer"),
    ("piege_ajouter_a_un_enum_parcouru_par_values",
     "regle_pont_madd_statut_vers_duree", "shares_data_with",
     "effet de bord rencontre en posant le pont"),
    ("regle_pont_madd_statut_vers_duree",
     "piege_ids_tete_tajwid_traduits_par_position", "shares_data_with",
     "les deux moities du raccord modele <-> app pour le tajwid"),
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
            print(f"  = deja present : {nid}")
            continue
        g["nodes"].append({
            "label": label, "rationale": rationale, "node_type": "concept",
            "id": nid, "community": 0, "norm_label": label.lower()})
        a += 1
    connus = {n["id"] for n in g["nodes"]}
    ar = 0
    for s, t, rel, pq in LIENS:
        if s not in connus or t not in connus:
            print(f"  ! cible absente : {s} -> {t}")
            continue
        g["links"].append({"source": s, "target": t, "relation_type": rel,
                           "source_location": pq, "rationale": pq})
        ar += 1
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step42.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, {len(g['links'])} aretes")


if __name__ == "__main__":
    main()
