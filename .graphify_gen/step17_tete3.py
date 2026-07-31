#!/usr/bin/env python3
"""Le passage a la tete 3 : pourquoi, ou on en est, et ce qui reste.

Debut du chantier `tete3-ecart-canonique` (branche dediee, 2026-07-31).
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("regle_preferer_une_tete_a_une_regle_ecrite",
     "[REGLE] Preferer une TETE a une regle ecrite a la main",
     "ARGUMENT DE L'UTILISATEUR (2026-07-31) : « je prefere gerer la regle C par "
     "modele, car il y a possibilite d'amelioration apres par entrainement ; "
     "sinon avec la regle C on ne peut pas ameliorer ». La mesure lui donne "
     "raison sur les trois points. (1) La regle C est un PLAFOND FIXE a 27 % de "
     "detection : deux tentatives d'amelioration ont echoue -- le forward au "
     "lieu du Viterbi n'a AUCUN effet, cibler la queue par negatifs durs fait "
     "PIRE (AUC 0,79 -> 0,67). (2) Une tete entrainee sur LES MEMES grandeurs "
     "(les logprobs) ne fait pas mieux : 26 %. Ce n'etait donc pas la formule "
     "qui etait mauvaise, c'est que les logprobs ont deja jete l'information -- "
     "ils sont la projection de 512 dimensions sur 1025 classes, apprise pour "
     "TRANSCRIRE. (3) La tete qui lit les 512 dimensions de l'encodeur gagne 4 "
     "points (31 %), et elle n'a ete entrainee que sur 1 265 phrases. "
     "COROLLAIRE : le plafond de la TETE est fixe par l'ENCODEUR. L'etape 1 l'a "
     "montre -- entrainer l'encodeur sur des phrases fautees a ameliore sa "
     "REPRESENTATION (transcription des fautes x1,8) sans deplacer sa "
     "PREFERENCE faute/canonique (restee a 22 %). D'ou la progression : regle C "
     "(fixe) -> tete (s'ameliore par les donnees) -> entrainement contrastif de "
     "l'encodeur (leve le plafond de la tete)."),
    ("mesure_export_deux_sorties_sans_regression",
     "[MESURE] Exporter l'etat de l'encodeur ne casse rien",
     "Le modele reexporte rend DEUX sorties : `logprobs` (batch, T, 1025) "
     "INCHANGEE et `encoder_state` (batch, T, 512) AJOUTEE. L'ordre compte -- "
     "logprobs d'abord, pour que le plugin Kotlin qui lit out[0] continue de "
     "fonctionner sans modification. VERIFIE hors device sur 20 s de recitation "
     "reelle : ecart maximal 1,41e-04 sur les logprobs, texte decode IDENTIQUE. "
     "VERIFIE SUR DEVICE le 2026-07-31 : modele pousse sur le Samsung "
     "(461 Mo, ancien sauvegarde en model.onnx.avant_tete3), la chaine "
     "transcrit normalement -- bande=8..15 conf=1,00, l'ancre progresse. "
     "PIEGE EVITE au passage : l'exporteur ecrit les poids A COTE "
     "(model.onnx 3 Mo + model.onnx.data 458 Mo) ; le fichier « marche » sur le "
     "PC parce que le .data est a cote, et aurait echoue sur le telephone ou "
     "seul model.onnx est copie. Refusion en un fichier unique."),
    ("attente_portage_kotlin_tete3",
     "[EN ATTENTE] Porter la tete 3 cote Kotlin",
     "CE QUI EST PRET : model.onnx a deux sorties deploye sur le Samsung, et "
     "tete3.json (16 833 parametres, 380 Ko) -- deux couches lineaires, entree "
     "= [etat encodeur moyenne sur les frames du mot (512), puis les 12 scores "
     "conditionnes par la cible]. "
     "CE QUI MANQUE : lire la seconde sortie dans FastConformerCtc, moyenner "
     "les 512 dimensions sur les frames du mot, appliquer les deux couches. "
     "POURQUOI LA TETE N'EST PAS DANS LE ONNX, et c'est voulu : elle a besoin de "
     "grandeurs CONDITIONNEES PAR LA CIBLE (score force du mot attendu, score de "
     "sa meilleure confusion) que seul l'appelant connait -- l'app sait quel mot "
     "est attendu, le modele non. Une tete qui ne lirait QUE l'acoustique a ete "
     "mesuree : 6 a 13 % de detection, la PIRE de toutes. Sans la cible, la "
     "question n'a pas de sens : un ص correct et un س correct sonnent tous deux "
     "corrects. "
     "Chantier isole sur la branche `tete3-ecart-canonique` ; la reference "
     "`recitation-v2` et le tag v2-frontiere-2.37pct restent intacts."),
]

LIENS = [
    ("regle_preferer_une_tete_a_une_regle_ecrite", "attente_portage_kotlin_tete3",
     "motive", None),
    ("mesure_export_deux_sorties_sans_regression", "attente_portage_kotlin_tete3",
     "prealable_fait", None),
    ("attente_portage_kotlin_tete3", "regle_cahier_des_charges_deux_tetes",
     "realise", None),
    ("regle_preferer_une_tete_a_une_regle_ecrite", "mesure_modele_deploye_une_seule_tete",
     "repond_a", None),
    ("attente_portage_kotlin_tete3", "piege_banc_bruit_depasse_effet_cherche",
     "jugeable_depuis", "le banc mesure de nouveau : 165/167 fenetres, +4 points visibles"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step17.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
