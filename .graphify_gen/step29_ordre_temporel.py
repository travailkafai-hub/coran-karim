#!/usr/bin/env python3
"""Ordre temporel des mots (Decideur.Statut.Deplace) : mesure du 2026-08-11 (commit 377e35f)."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("symptome_permutation_de_mots_validee_verte",
     "[SYMPTOME] Le recitateur dit deux groupes d'un verset DANS LE DESORDRE, tout ressort vert -- nait dans Decideur (aucun terme de position)",
     "Constat utilisateur : « pour AB CD EF, j'ai dit AB EF CD, tout est valide ». "
     "L'ordre etait deja verifie A L'INTERIEUR d'une fenetre (LCS strictement "
     "croissante dans Localisateur.apparier, Viterbi monotone dans "
     "AligneurForce.aligner), mais une violation d'ordre y produisait du "
     "SILENCE, jamais un verdict : le groupe declasse sortait de `attestes` "
     "sans aucun signal, `sansCreneau` retirait le droit de voter. Le "
     "desordre etait traite comme une ABSENCE DE PREUVE. La couche ou le "
     "symptome NAIT n'est ni le localisateur ni l'aligneur (qui font leur "
     "travail correctement DANS une fenetre) : c'est le Decideur, dont les "
     "deux chemins qui figent un vert sur une observation unique (`nette`, "
     "le secours anti-Omis) n'ont aucun terme de position."),

    ("mesure_observations_portent_deja_un_temps_jamais_lu",
     "[MESURE] Observation.debutAbs/finAbs existent depuis le debut, zero lecture par une decision avant le 2026-08-11",
     "Grep exhaustif sur tout le paquet recitation2 (2026-08-11) : ces deux "
     "champs n'etaient lus QUE par `voixSurPlage` (rejouer l'audio) et "
     "`tracerMot` (journal). Aucune decision (Localisateur, AligneurForce, "
     "Decideur) ne les regardait -- tout raisonnait sur des index de mots. "
     "Journal reel, session sourate 103 verset 3, 2026-08-11 13:20:05 : la "
     "fenetre f=17 entend `صَبْرَ وَتَوَاصَوْا۟ بِ بِٱلْحَقِّ` -- la FIN du "
     "verset avant son DEBUT -- et c'est precisement la fenetre qui ne juge "
     "rien (`bande=inconnue`), les mots encadrants ressortant `definitif:vert`, "
     "zero `SAUT REFUSE`."),

    ("regle_deplace_temps_dimension_du_jugement",
     "[REGLE] Le temps devient une dimension du jugement : Statut.Deplace, brancne aux deux seuls chemins qui figent un vert sur une observation unique",
     "Pour le mot i : sa preuve la plus PRECOCE commence-t-elle apres la FIN "
     "de la preuve la plus TARDIVE d'un mot POSTERIEUR j > i ? Si oui, aucune "
     "lecture de i n'est en place -- `Deplace` (jamais rouge, jamais fige, "
     "recalcule a chaque fenetre comme `Omis`). Deux mesures ASYMETRIQUES : "
     "le cote ACCUSE (`debutPropre`) est permissif (observation au bord "
     "acceptee), le cote ACCUSATEUR (`finVotante`) est strict (seules les "
     "votantes accusent) -- c'est ce qui protege la repetition legitime. "
     "Branche aux DEUX chemins qui figent un vert sur une observation unique "
     "(`nette` et le secours anti-Omis) : un seul des deux aurait laisse une "
     "fuite. Cote Dart, `deplace` -> `WordStatus.unclear` (orange, jamais "
     "rouge -- le mot a bien ete prononce)."),

    ("mesure_48_48_tests_apres_deplace_dont_discriminant",
     "[MESURE] 48/48 tests JVM verts apres Deplace (44/44 avant), sourates 94/107 (passages repetes) inchangees ; controle negatif confirme la cause",
     "4 tests neufs, dont deux qui isolent le discriminant : une permutation "
     "de deux groupes est signalee `Deplace`, une repetition legitime (mot "
     "revu seulement au bord pendant la lecture en place, puis redit) ne "
     "l'est JAMAIS. Controle negatif : gates neutralisees (`if (false)`), "
     "exactement les deux tests de detection echouent, rien d'autre -- le "
     "reste de la suite (dont `un recitateur qui REPETE est suivi`) reste "
     "vert intact. Limite nommee : `Deplace` et `unclear` partagent la meme "
     "couleur orange a l'ecran, les distinguer visuellement est une decision "
     "d'IHM separee, non prise ici."),
]

LIENS = [
    ("mesure_observations_portent_deja_un_temps_jamais_lu", "symptome_permutation_de_mots_validee_verte",
     "explique", "l'information existait deja et n'etait lue par personne -- c'est la cause du symptome"),
    ("regle_deplace_temps_dimension_du_jugement", "mesure_observations_portent_deja_un_temps_jamais_lu",
     "s_appuie_sur", "utilise debutAbs/finAbs deja presents, aucune nouvelle instrumentation cote chaine"),
    ("mesure_48_48_tests_apres_deplace_dont_discriminant", "regle_deplace_temps_dimension_du_jugement",
     "verifie", "mesure avant/apres + controle negatif sur le correctif"),
]


def sha(ref="HEAD"):
    try:
        return subprocess.run(["git", "rev-parse", ref], capture_output=True,
                              text=True, cwd=RACINE, timeout=5).stdout.strip()
    except Exception:
        return ""


def main():
    g = json.loads(GRAPHE.read_text(encoding="utf-8"))
    connus = {n["id"] for n in g["nodes"]}
    a = 0
    for nid, label, rationale in NOEUDS:
        if nid in connus:
            continue
        g["nodes"].append({
            "label": label, "file_type": "concept",
            "source_file": "app/android/app/src/main/kotlin/com/corankarim/coran_karim/recitation2/Decideur.kt",
            "source_location": None, "source_url": None,
            "captured_at": "2026-08-11", "author": None, "contributor": None,
            "rationale": rationale, "_origin": "semantic",
            "id": nid, "community": 0, "norm_label": label.lower()})
        a += 1
    connus = {n["id"] for n in g["nodes"]}
    ar = 0
    for s, t, rel, pq in LIENS:
        if s not in connus or t not in connus:
            print(f"  ! cible absente : {s} -> {t}"); continue
        g["links"].append({"source": s, "target": t, "relation_type": rel,
                           "source_location": pq, "rationale": pq})
        ar += 1
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step29.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, {len(g['links'])} aretes")


if __name__ == "__main__":
    main()
