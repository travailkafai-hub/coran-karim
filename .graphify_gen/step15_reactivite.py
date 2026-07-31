#!/usr/bin/env python3
"""La reactivite : six essais, deux retenus, et la contrainte a supprimer.

Journee du 2026-07-31, seconde moitie. Meme principe : on enrichit, on
n'ecrase pas, et le `rationale` porte le CHIFFRE, pas l'intention.
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("regle_couper_est_la_mauvaise_contrainte",
     "[REGLE] Dependre de savoir OU couper est une mauvaise contrainte",
     "FORMULE PAR L'UTILISATEUR le 2026-07-31 : « toute l'application depend de "
     "savoir couper au bon moment, c'est pas bon comme contrainte ». C'est la "
     "cle qui a debloque une journee entiere. L'app doit trancher AVANT de "
     "savoir ou finissent les mots -- ce qu'elle cherche justement a decouvrir. "
     "Six essais de l'agent ont cherche OU couper ; les deux qui ont marche "
     "font en sorte que l'endroit de la coupe COMPTE MOINS. Le garde-fou du "
     "projet nomme deja ce defaut : « frontiere au mauvais endroit -- une "
     "couche decide de ce qu'elle n'a pas les moyens de savoir »."),
    ("solution_curseur_glissant",
     "[SOLUTION] Curseur glissant : fenetre de LONGUEUR FIXE qui avance",
     "IDEE DE L'UTILISATEUR : « le modele ne juge qu'un mot ; avoir un mot coupe "
     "c'est pas grave, il sera entier quand on deplace le curseur ». MESURE, "
     "recette scriptee sourate 2 depart v6 : attente mediane 10,2 s -> 3,1 s, "
     "max 24,4 s -> 10,5 s, taux 2,61 % -> 3,05 %, ZERO mot non juge, ZERO rouge "
     "sans preuve. Ce qui le distingue des quatre echecs precedents : ceux-la "
     "partaient de `derniereCoupe`, donc une fenetre qui GROSSISSAIT jusqu'a "
     "30 s et etait RELOCALISEE ENTIEREMENT toutes les 2-3 s ; la LCS devait "
     "reapparier des dizaines de mots a chaque passage. Ici la fenetre fait 9 s "
     "et AVANCE : meme petit nombre de mots a chaque appel, et un mot du bord "
     "n'est pas juge -- il le sera au passage suivant, au centre."),
    ("solution_coupe_frontiere_de_mot",
     "[SOLUTION] Couper a la FRONTIERE DE MOT, plus au minimum d'energie",
     "MESURE : 3,05 % -> 2,37 % a attente inchangee (3,1 s), donc MEILLEUR QUE "
     "LA REFERENCE SUR LES DEUX AXES (10,2 s / 2,61 %). L'energie ne porte pas "
     "la frontiere de mot : une occlusive arabe a une phase peu energique AU "
     "MILIEU d'un mot, indiscernable d'une pause. Deja mesure le 2026-07-28 sur "
     "la v1 (47,4 % des coupes en plein mot, 19 des 22 mots non verts en etant "
     "les victimes) ; la v2 avait herite du meme defaut via `posMinRms`. "
     "L'information manquait alors qu'elle etait DEJA dans la chaine : "
     "l'alignement force rend la derniere frame de chaque mot. On inverse donc "
     "l'ordre -- aligner PUIS couper. Segmentation *word-boundary-aware* de la "
     "litterature (WhisperAlign). Garde-fous : seuls les mots INTERIEURS "
     "remontent une frontiere, elle ne sert que si aucun vrai silence n'a ete "
     "trouve, repli sur l'energie sinon."),
    ("mort_apercu_fenetre_qui_grossit",
     "[MORT] Apercu periodique depuis la derniere coupe (4 variantes)",
     "QUATRE ESSAIS, QUATRE ECHECS le 2026-07-31, attente / non verts : bande "
     "libre 2,2 s / 52,44 % | bande figee 11,1 s / 3,29 % | ancre + 6 mots "
     "8,5 s / 46,52 % | queue cachee au localisateur 3,3 s / 56,96 %. Signature "
     "constante : 95 % des erreurs en TROIS BLOCS CONSECUTIFS, `entendu` vide, "
     "`free` proche de 0 -- le modele entend bien, on lui demande les mauvais "
     "mots. Cause : la fenetre part de `derniereCoupe`, grossit jusqu'a 30 s et "
     "est relocalisee entierement a chaque apercu. Les quatre variantes "
     "changeaient ce qui se passe APRES la fenetre (bande, verrouillage, queue) "
     "sans jamais remettre en cause la fenetre elle-meme. A NE PAS RETENTER "
     "sous cette forme : le curseur glissant est la version qui marche."),
    ("mort_borner_maxbloc",
     "[MORT] Borner maxBloc pour reduire l'attente",
     "MESURE : maxBloc 30 s -> 12 s donne 10,1 s d'attente (contre 10,2 s, donc "
     "AUCUN gain) et 13,04 % de non verts (contre 2,61 %). Degrade sans rien "
     "apporter. La coupe tombait pourtant deja au point le plus silencieux "
     "(posMinRms), ce n'etait donc pas la garde a 18 s de 2026-07-29 qui "
     "coupait a un endroit arbitraire."),
    ("piege_5_6s_de_contexte_gauche_ne_coute_rien",
     "[PIEGE] Confondre le contexte GAUCHE avec une attente",
     "att_context [70,13] = 70 frames a gauche (5,6 s) et 13 a droite (1,04 s), "
     "a 80 ms la frame. Les 5,6 s sont de l'audio DEJA ENREGISTRE : le modele "
     "ne les attend pas, il les relit. Reduire ce contexte ne ferait gagner "
     "AUCUNE milliseconde et ne ferait que degrader la precision. Le seul delai "
     "incompressible est 1,04 s -- et il existe parce que beaucoup de sons ne "
     "sont identifiables que par ce qui les suit (relachement des occlusives, "
     "soukoun, madd, coarticulation). Les 10 s d'attente venaient de l'app qui "
     "attendait un silence, jamais du modele."),
    ("attente_portage_streaming_a_etat",
     "[EN ATTENTE] Streaming a etat : demontre fonctionnel, non porte",
     "`model_streaming.onnx` est deja exporte (shift 112 frames = 1,12 s, 14 "
     "frames de sortie par appel, cache_last_channel/cache_last_time propages). "
     "VERIFIE le 2026-07-31 en Python sur 30 s de recitation : le texte decode "
     "par tranches est identique au texte du modele plein en debut et en fin, "
     "avec un trou au milieu du a MON arithmetique de fenetrage (364 frames "
     "produites contre 376), pas au modele. ⚠️ Un premier verdict « divergent » "
     "avait ete rendu sur un ecart numerique moyen de 2,97 -- metrique fausse, "
     "elle mesurait le bruit sur 1024 classes improbables alors que l'argmax "
     "etait IDENTIQUE partout. Le mecanisme est dans le code NeMo, pas dans un "
     "article : conformer_encoder.py ligne 636, `drop_extra_pre_encoded` = "
     "1 + (pre_encode_cache_size-1)//subsampling = 2, applique par l'encodeur "
     "lui-meme. Supprimerait le retraitement d'audio qu'impose le curseur."),
]

LIENS = [
    ("solution_curseur_glissant", "regle_couper_est_la_mauvaise_contrainte", "applique", None),
    ("solution_coupe_frontiere_de_mot", "regle_couper_est_la_mauvaise_contrainte",
     "applique", "on ne cherche plus un silence, on utilise une frontiere connue"),
    ("mort_apercu_fenetre_qui_grossit", "solution_curseur_glissant", "corrige_par",
     "meme idee, mais fenetre de longueur FIXE au lieu de croissante"),
    ("mort_borner_maxbloc", "regle_couper_est_la_mauvaise_contrainte", "ne_corrige_pas", None),
    ("solution_coupe_frontiere_de_mot", "couche_v2_b_fenetres", "modifie", None),
    ("solution_curseur_glissant", "couche_v2_b_fenetres", "modifie", None),
    ("attente_portage_streaming_a_etat", "regle_couper_est_la_mauvaise_contrainte",
     "supprime", "plus aucun refenetrage, donc plus rien a arbitrer"),
    ("piege_5_6s_de_contexte_gauche_ne_coute_rien", "attente_portage_streaming_a_etat",
     "eclaire", None),
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
    ajoutes = 0
    for nid, label, rationale in NOEUDS:
        if nid in connus:
            continue
        g["nodes"].append({
            "label": label, "file_type": "concept",
            "source_file": "SOLUTIONS_RECITATION_V2.md", "source_location": None,
            "source_url": None, "captured_at": "2026-07-31", "author": None,
            "contributor": None, "rationale": rationale, "_origin": "semantic",
            "id": nid, "community": 0, "norm_label": label.lower(),
        })
        ajoutes += 1
    connus = {n["id"] for n in g["nodes"]}
    aretes = 0
    for s, t, rel, pourquoi in LIENS:
        if s not in connus or t not in connus:
            print(f"  ! cible absente : {s} -> {t}")
            continue
        g["links"].append({"source": s, "target": t, "relation_type": rel,
                           "source_location": pourquoi, "rationale": pourquoi})
        aretes += 1
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step15.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
