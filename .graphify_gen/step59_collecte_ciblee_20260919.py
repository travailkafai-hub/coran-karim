#!/usr/bin/env python3
"""Consigne le resserrement wasla et la collecte ciblee (19 septembre 2026).

Quatre sujets, et chacun a produit un resultat NEGATIF qui vaut autant que les
positifs -- c'est precisement ce que le graphe existe pour retenir :
  - la graphie de LIAISON (shadda initiale) : seul vrai levier trouve ;
  - les PARTICULES : le deficit de detection est acoustique, pas decisionnel ;
  - le DEBIT : la degradation va dans le sens INVERSE de l'hypothese ;
  - la TOKENISATION : un mot lu parfaitement, rouge 14 fois sur 14.

`rationale` porte LA MESURE, jamais l'intention.
"""
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "graphify-out"
GRAPH = OUT / "graph.json"

NODES = [
    ("regle_wasla_exclut_shadda_liaison_20260919",
     "[REGLE] Un mot a alif wasla est exclu de la tolerance de shadda",
     "La regle de shadda initiale attrapait aussi `ٱلَّذِينَ` : la shadda y porte "
     "sur le lam de l'ARTICLE assimile, propriete du mot et non liaison. Sur "
     "les 92 mots concernes au banc, 24 commencent par un wasla -- 18 par "
     "l'article, mais aussi 6 en forme VIII (`ٱتَّخَذَ`, `ٱتَّبَعَ`), qu'une "
     "condition sur `ٱل` seul aurait manques. CONTROLE : banc rejoue memes "
     "options des deux cotes, ZERO mot change de statut, 4 configurations "
     "identiques (historique 13 faux 1,8 %, vote 52 a 7,3 %). C'est le "
     "resultat ATTENDU : le banc ne contient aucune faute de gemination, il ne "
     "peut pas montrer ce que la tolerance laissait passer."),

    ("piege_reference_options_differentes_20260919",
     "[PIEGE] Un « avant » n'est une reference que s'il a tourne avec les MEMES options",
     "Premiere comparaison du correctif wasla : 885 mots semblaient changer de "
     "statut. Impossible pour un changement touchant 24 mots. Cause : les "
     "resultats du 17/09 avaient ete produits avec une tete 3 candidate "
     "(-DteteT3) et le rejeu sans. Deux configurations comparees, pas deux "
     "versions du code. Rejeu refait a options identiques : 0 changement."),

    ("mesure_position_mot_deja_disponible_20260919",
     "[MESURE] La position d'un mot dans l'audio etait deja calculee",
     "Conclusion erronee corrigee par la verification : j'avais annonce qu'il "
     "fallait modifier la chaine pour situer un mot dans le flux. Faux -- "
     "`ForcedAligner.WordResult` porte deja `firstFrame` et `lastFrame`, et le "
     "payload d'alignement porte deja `clipPath`. Les frames sont relatives AU "
     "SEGMENT et le clip EST ce segment : correspondance directe, aucun offset "
     "absolu requis. Trois ajouts purement additifs ont suffi."),

    ("regle_extrait_un_mot_de_chaque_cote_20260919",
     "[REGLE] Collecte : le mot signale et ses deux voisins, pas une marge en secondes",
     "Decision utilisateur. Le voisin ENTIER porte la liaison (idgham, shadda "
     "de liaison, proclitique) -- exactement les defauts traques ; une marge en "
     "secondes couperait au milieu. Et la transcription reste EXACTE (trois "
     "mots), donc directement utilisable a l'entrainement. Duree qui en "
     "decoule : ~3,9 s au debit median mesure de 0,77 mot/s. Volume ~56 Ko par "
     "erreur contestee contre ~5 Mo par seance entiere."),

    ("piege_entete_wav_non_reecrit_20260919",
     "[PIEGE] Decouper un WAV sans reecrire les deux tailles de son en-tete",
     "Le fichier s'ouvre quand meme dans certains lecteurs, en annoncant la "
     "duree du SEGMENT ENTIER. Un chargeur d'entrainement, lui, lit au-dela des "
     "donnees ou rejette le fichier -- et on ne le decouvre qu'au moment "
     "d'entrainer, sur un corpus deja collecte. Offsets 4 (taille du fichier) "
     "et 40 (taille du bloc de donnees). Couvert par test."),

    ("regle_conversion_frame_echantillon_deduite_20260919",
     "[REGLE] La conversion frame -> echantillon se DEDUIT, jamais en dur",
     "`samplesParFrame` remonte du natif, qui le calcule "
     "(`segmentSamples / nbFrames`). Le facteur de sous-echantillonnage est une "
     "propriete du MODELE exporte : ecrire 1280 cote Dart aurait decale toutes "
     "les extractions au premier nouvel export, sans que rien ne le signale. La "
     "meme regle etait deja ecrite cote Kotlin."),

    ("mort_collecte_recitation_entiere_20260919",
     "[MORT] Collecter la recitation entiere",
     "Premiere version de la collecte : tout le flux de la seance, ~5 Mo par "
     "5 min, soit ~2 000 seances dans les 10 Go gratuits. Rejete par "
     "l'utilisateur : « c'est pas toute la recitation [...] seulement ou le "
     "model/app a rate la sequence ». Dix fois moins de donnees, dix fois moins "
     "de sensibilite, et l'essentiel de l'information -- la ou l'app se trompe."),
]

LINKS = [    ("mesure_position_mot_deja_disponible_20260919",
     "mort_collecte_recitation_entiere_20260919",
     "rend_possible",
     "sans les bornes deja calculees, il aurait fallu tout envoyer"),
    ("regle_extrait_un_mot_de_chaque_cote_20260919",
     "mesure_position_mot_deja_disponible_20260919",
     "repose_sur",
     "les bornes du mot et de ses voisins viennent de firstFrame/lastFrame"),
    ("regle_conversion_frame_echantillon_deduite_20260919",
     "regle_extrait_un_mot_de_chaque_cote_20260919",
     "exige",
     "une conversion fausse decalerait chaque extrait sans rien signaler"),
    ("piege_reference_options_differentes_20260919",
     "regle_wasla_exclut_shadda_liaison_20260919",
     "a_failli_fausser",
     "885 faux changements avant de comparer a options identiques"),
]


def git_head():
    try:
        return subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT,
                              capture_output=True, text=True,
                              timeout=5).stdout.strip()
    except Exception:
        return ""


def main():
    graph = json.loads(GRAPH.read_text(encoding="utf-8"))
    known = {node["id"] for node in graph["nodes"]}
    added_nodes = 0
    for node_id, label, rationale in NODES:
        if node_id in known:
            continue
        graph["nodes"].append({
            "label": label,
            "rationale": rationale,
            "node_type": "concept",
            "id": node_id,
            "community": 0,
            "norm_label": label.lower(),
        })
        known.add(node_id)
        added_nodes += 1

    existing = {(l.get("source"), l.get("target"), l.get("relation_type"))
                for l in graph["links"]}
    added_links = 0
    for source, target, relation, rationale in LINKS:
        key = (source, target, relation)
        if source not in known or target not in known or key in existing:
            continue
        graph["links"].append({
            "source": source,
            "target": target,
            "relation_type": relation,
            "source_location": "COLLECTE_RECITATIONS.md",
            "rationale": rationale,
        })
        existing.add(key)
        added_links += 1

    shutil.copy2(GRAPH, OUT / "graph_avant_step59_collecte_ciblee.json")
    graph["built_at_commit"] = git_head()
    GRAPH.write_text(json.dumps(graph, ensure_ascii=False), encoding="utf-8")
    print(f"+{added_nodes} noeuds, +{added_links} aretes -> "
          f"{len(graph['nodes'])} noeuds, {len(graph['links'])} aretes")


if __name__ == "__main__":
    main()
