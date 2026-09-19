#!/usr/bin/env python3
"""Consigne pourquoi la decision est aveugle aux ajouts (19 septembre 2026).

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
    ("mesure_gop_aveugle_aux_ajouts_20260919",
     "[MESURE] Le gop ne peut pas voir une faute par AJOUT",
     "Session d'erreurs forcees : 33 mots juges, 29 verts, AUCUNE faute "
     "signalee -- alors que le transcript libre les contient toutes. `gop = "
     "forced - free` est un ECART : mot 29, le verdict passe de ROUGE (obs 1, "
     "gop -1,70) a VERT (obs 3, gop -0,14) parce que `free` se degrade "
     "(-0,22 -> -0,35) en meme temps que `forced` s'ameliore (-1,92 -> -0,48). "
     "Mot 32 : forced = free = -0,22, donc gop = 0,00 EXACTEMENT. "
     "L'application verifie que le mot attendu est PRESENT, jamais qu'il n'y a "
     "rien d'autre."),

    ("piege_verdict_juste_ecrase_par_les_suivantes_20260919",
     "[PIEGE] Un premier verdict JUSTE efface par les observations suivantes",
     "Mot 29 : rouge a la premiere observation, vert definitif a la troisieme. "
     "Ce n'est donc pas un probleme de seuil mais d'accumulation de preuves. "
     "A instruire : que fait l'accumulation d'un premier verdict tres negatif."),

    ("mesure_decalage_alignement_sur_insertion_20260919",
     "[MESURE] Une insertion decale l'alignement et produit un faux `omis`",
     "Mot 25 `وَمَآ` juge sur 2 FRAMES (160 ms) avec pour lecture `فَ` seul ; "
     "mot 28 `قَبْلِكَ` recoit `وَبِ` -- le debut du mot SUIVANT -- et sort "
     "`omis`, le verdict le plus grave de l'app, alors que le transcript f=24 "
     "contient `أُنزِلَ مِن قَبْلِكَ` en clair. Tant que ce decalage existe, "
     "aucune regle aval ne peut viser le bon mot."),

    ("mort_controle_par_intrus_de_texte_20260919",
     "[MORT] Signaler les mots decodes absents du texte attendu de la bande",
     "Proposition utilisateur d'une passe longue de controle -- elle existe "
     "deja (f=25 fait 11,84 s et contient le `فَ` insere). Mesure sur le banc "
     "d'erreurs reelles : PAR FENETRE avec filtres, 96 justes / 30 faux, 76 % "
     "de precision -- chiffre flatteur. PAR MOT et contre l'existant : "
     "+19 detections pour +387 FAUX, soit vingt fausses accusations par faute "
     "rattrapee. Cause : une fenetre qui porte un intrus accuse TOUTE sa bande "
     "-- un intrus dans huit mots en salit huit. La regle sait dire « il y a "
     "une faute ici », pas « c'est ce mot-la »."),

    ("piege_mesurer_un_signal_sans_le_comparer_a_l_existant_20260919",
     "[PIEGE] Mesurer la qualite d'un signal au lieu du GAIN NET",
     "Troisieme occurrence du mois. La regle d'intrus affichait 76 % de "
     "precision par fenetre -- de quoi justifier une implementation. Rapportee "
     "au MOT et a ce que la chaine detecte DEJA : +19 detections pour +387 "
     "faux. La premiere mesure aurait fait implementer, la seconde l'interdit."),
]

LINKS = [    ("mort_controle_par_intrus_de_texte_20260919",
     "mesure_decalage_alignement_sur_insertion_20260919",
     "bute_sur",
     "l'intrus est vu mais ne peut pas etre attribue au bon mot"),
    ("mort_controle_par_intrus_de_texte_20260919",
     "piege_mesurer_un_signal_sans_le_comparer_a_l_existant_20260919",
     "illustre",
     "76 % de precision par fenetre, +19/+387 par mot"),
    ("piege_verdict_juste_ecrase_par_les_suivantes_20260919",
     "mesure_gop_aveugle_aux_ajouts_20260919",
     "aggrave",
     "le seul verdict correct du mot 29 a ete efface"),
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
            "source_location": "benchmark/DECISION_AVEUGLE_AUX_AJOUTS_20260919.md",
            "rationale": rationale,
        })
        existing.add(key)
        added_links += 1

    shutil.copy2(GRAPH, OUT / "graph_avant_step60_decision_ajouts.json")
    graph["built_at_commit"] = git_head()
    GRAPH.write_text(json.dumps(graph, ensure_ascii=False), encoding="utf-8")
    print(f"+{added_nodes} noeuds, +{added_links} aretes -> "
          f"{len(graph['nodes'])} noeuds, {len(graph['links'])} aretes")


if __name__ == "__main__":
    main()
