#!/usr/bin/env python3
"""Le dernier maillon de la tete 3 ne doit PAS etre pose sur le modele actuel.

Trouve en ouvrant tete3.json pour le cabler (2026-07-31, fin de journee).
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_tete3_sans_gain_sur_modele_app",
     "[MESURE] La tete 3 n'apporte RIEN sur le modele de l'app",
     "Sur les 189 phrases tenues a l'ecart, audio reellement faute, detection a "
     "2 % de collateral : regle C seule 36/149 = 24,2 %, tete 3 32/149 = "
     "21,5 %. z = 0,55, tres loin du seuil 1,96 -- les deux sont "
     "INDISCERNABLES. L'intervalle a 95 % sur n=149 vaut +/- 6,8 points, il "
     "avale largement l'ecart. "
     "LES 31 % N'ONT JAMAIS ETE MESURES SUR CE MODELE : ils viennent de "
     "`fastconformer-causal-v4-phrases`, l'encodeur REENTRAINE sur les phrases "
     "fautees (defaut --nemo de tete_encodeur_ecart.py). Le gain de la tete est "
     "donc un gain de L'ENCODEUR, pas de la tete -- ce qui confirme le "
     "corollaire deja au graphe : le plafond de la tete est fixe par "
     "l'encodeur. "
     "CONSEQUENCE : brancher la tete sur le modele deploye serait poser un "
     "mecanisme mesure sans gain, avec en prime le risque de parite "
     "Python/Kotlin sur les 12 caracteristiques. Refus bloquant (regle du "
     "superviseur). Le commit de414cd du matin le disait deja dans son titre -- "
     "« et la mesure dit de ne pas s'en servir la » ; l'information a ete "
     "perdue de vue en cours de journee, c'est exactement ce que le graphe "
     "existe pour empecher."),
    ("attente_choix_modele_avant_de_brancher_tete3",
     "[EN ATTENTE] Choisir l'encodeur AVANT de poser le dernier maillon",
     "Le portage est arrete a 1/2 : l'etat de l'encodeur remonte jusqu'a la "
     "chaine (mesure, sans regression), la tete n'est pas cablee au Decideur. "
     "Deux voies, a arbitrer par l'utilisateur. "
     "(A) DEPLOYER `fastconformer-causal-v4-phrases`, ou la tete vaut 31 % "
     "contre 27 % a la regle. Gain reel mais il faut une recette de "
     "non-regression complete : cet encodeur a ete entraine sur des phrases "
     "fautees, rien ne garantit qu'il tienne les 2,37 % de mots non verts sur "
     "de la recitation juste -- c'est precisement le taux que la reference "
     "protege. "
     "(B) NE RIEN BRANCHER et garder la regle C. Cout du statu quo : zero, "
     "puisque la tete ne fait pas mieux ici. "
     "Dans les deux cas Tete3.kt (chargement + deux couches + verifierParite) "
     "reste utile : il est independant du modele choisi."),
]

LIENS = [
    ("mesure_tete3_sans_gain_sur_modele_app", "attente_portage_kotlin_tete3",
     "arrete", "le dernier maillon ne doit pas etre pose sur ce modele-ci"),
    ("mesure_tete3_sans_gain_sur_modele_app",
     "regle_preferer_une_tete_a_une_regle_ecrite", "nuance",
     "la tete ne gagne que si l'encodeur a bouge -- le gain est celui de l'encodeur"),
    ("mesure_tete3_sans_gain_sur_modele_app", "mesure_modele_deploye_une_seule_tete",
     "confirme", None),
    ("attente_choix_modele_avant_de_brancher_tete3",
     "mesure_tete3_sans_gain_sur_modele_app", "decoule_de", None),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step19.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
