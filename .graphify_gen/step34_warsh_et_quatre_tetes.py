#!/usr/bin/env python3
"""Warsh (YEH BARREE), modele a quatre tetes INT8, et la fusion des deux chantiers.

⚠️ PROVENANCE DES CHIFFRES : ces noeuds TRANSCRIVENT les mesures ecrites par
l'utilisateur dans les messages des commits 0839502, 401b1da et 497bbc8. Elles
n'ont pas ete refaites ici -- rien n'est ajoute, rien n'est arrondi, et aucune
conclusion n'est tiree au-dela de ce que ces messages affirment.
"""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("piege_yeh_barree_warsh_lettre_prise_pour_un_diacritique",
     "[PIEGE] Le YEH BARREE (U+06D2) du Warsh est une LETTRE, pas un diacritique -- 2 921 mots sortaient rouges quoi que recite l'utilisateur",
     "Le mushaf Warsh ecrit le ya final avec YEH BARREE (U+06D2) : فے، الذے، "
     "شےء, 2 996 fois. La classe `_harakat` ne le retirait donc pas, et « فے » "
     "attendu ne pouvait JAMAIS correspondre a « في » produit par le modele. "
     "MESURE sur le texte entier : le squelette des mots Warsh correspondait a "
     "94,29 % de ce que le modele peut ecrire, il correspond ensuite a "
     "98,06 % -- 2 921 mots concernes. AUCUN EFFET SUR LE HAFS, et ce n'est "
     "pas une opinion : ce caractere apparait 0 fois dans le texte Hafs, 0 "
     "fois dans les 1 024 tokens du vocabulaire, 0 fois dans les 19 001 mots "
     "de `word_tokens.json` ; controle exhaustif sur les 6 236 versets Hafs, 0 "
     "verset dont la normalisation change. (commit 0839502)"),

    ("piege_convinteger_int8_refuse_par_ort_1_20",
     "[PIEGE] Un modele INT8 se charge puis est REFUSE a la compilation du graphe : ConvInteger n'existait qu'en UINT8 avant ORT 1.20",
     "Symptome : `ORT_NOT_IMPLEMENTED - Could not find an implementation for "
     "ConvInteger(10) node with name node_conv2d_quant`. Inspection du "
     "fichier : 61 `ConvInteger` a poids INT8 (elem_type=3) et 205 "
     "`MatMulInteger`. Le noyau CPU de `ConvInteger` n'etait enregistre qu'en "
     "UINT8 jusqu'apres la 1.20 -- d'ou la signature trompeuse : des MatMul "
     "qui PASSENT et des Conv qui BLOQUENT sur le meme fichier. Verifie en "
     "local : le MEME fichier tourne sous onnxruntime 1.26.0 et rend ses "
     "quatre sorties finies. VOIE ECARTEE, et pourquoi : reecrire les poids "
     "INT8 en UINT8 est une transformation EXACTE (ajouter 128 au poids ET a "
     "son point zero laisse `w - w_zp` inchange), mais elle demandait de "
     "retoucher 61 tenseurs pour eviter une montee de version qui apporte "
     "aussi six versions de correctifs. (commit 401b1da)"),

    ("var_modele_quatre_tetes_int8_129mo",
     "modele_4tetes_2026-08-21 : 129 Mo INT8 contre 458 Mo FP32, vocabulaire Hafs INCHANGE (meme MD5)",
     "Ce qui a ete verifie AVANT de toucher a quoi que ce soit : les 9 "
     "empreintes MD5 du paquet (model.onnx compris) toutes OK ; l'interface "
     "ONNX -- entree `audio_signal` (le mel, jamais l'audio brut : piege tombe "
     "DEUX fois dans ce projet) et les quatre sorties dans l'ordre "
     "contractuel, `logprobs` en position 0 ; le decalage `encoder_state` "
     "2 -> 3 SANS EFFET puisque le plugin lit par NOM "
     "(`results.get(ENCODER_STATE_OUTPUT)`), seul `logprobs` etant lu par "
     "position ; et surtout le vocabulaire Hafs IDENTIQUE a celui du modele "
     "sortant (meme MD5, 3e20169f...6ea4), donc `word_tokens.json` repris tel "
     "quel. C'etait le plus gros risque du remplacement : il est leve par la "
     "mesure et non par l'espoir. (commit 401b1da)"),

    ("regle_seuils_tajwid_lire_les_deux_formats",
     "[REGLE] Lire les DEUX formats de seuils tajwid plutot que convertir -- aplatir jetterait le rappel et le taux d'invention mesures",
     "L'ancien fichier est `{\"seuils\": {nom: 0.87}}`, le nouveau "
     "`{\"regles\": {nom: {\"seuil\":.., \"rappel\":.., \"invention\":.., "
     "\"n_verif\":..}}}`. Le code lit les deux. Aplatir le fichier livre pour "
     "coller a l'ancien format jetterait le rappel et le taux d'invention "
     "MESURES qui ont fixe chaque seuil -- c'est exactement ce qui rend un "
     "seuil discutable plus tard : savoir ce qu'il coute. Lire les deux "
     "permet en plus de revenir a l'ancien modele sans toucher au code. "
     "(commit 401b1da)"),

    ("regle_hafs_par_mp3quran_warsh_par_everyayah",
     "[REGLE] Le Hafs passe par MP3Quran, le Warsh par everyayah -- et aucun des deux ne depend de Quran Foundation",
     "Conflit central de la fusion, resolu en gardant LES DEUX cotes : la "
     "liste reduite a Al-Afasy (le seul avec une correction audio sans Quran "
     "Foundation : MP3Quran + segments mot-a-mot precalcules) ET les deux "
     "recitateurs Warsh servis depuis everyayah (le Warsh n'existe pas chez "
     "quran.com). Les deux tiennent ensemble, et suppriment tous deux la "
     "dependance a QF -- ce que les deux chantiers cherchaient. NOTE MESUREE "
     "le 2026-08-21 : MP3Quran sert AUSSI le Warsh (riwaya 2 de son API, 13 "
     "recitateurs, dont Abdul Basit id=51 moshaf=52 avec les 114 sourates). Y "
     "passer donnerait au Warsh le meme chemin qu'au Hafs, mais exige un "
     "`word_segments` Warsh QUI N'EXISTE PAS : celui d'aujourd'hui est cale "
     "sur Al-Afasy ET sur le texte Hafs. (commit 497bbc8)"),

    ("piege_fusionner_le_graphe_en_choisissant_un_cote",
     "[PIEGE] Resoudre un conflit sur graph.json en prenant UNE version perd des mesures -- exactement ce que le graphe existe pour empecher",
     "A la fusion des deux chantiers, ni l'une ni l'autre version n'etait un "
     "sur-ensemble : 5 noeuds n'existaient que cote Warsh "
     "(`mesure_warsh_rasm_identique_a_99_pourcent`, "
     "`limite_timings_mot_a_mot_estimes_en_warsh`, "
     "`regle_riwaya_point_de_bascule_unique`...) et 37 que cote Hafs. Prendre "
     "une version aurait donc silencieusement supprime des mesures deja "
     "payees. Fusionne : 1 659 noeuds, 2 612 aretes. Regle : sur ce fichier, "
     "un conflit se resout par UNION, jamais par choix. (commit 497bbc8)"),
]

LIENS = [
    ("var_modele_quatre_tetes_int8_129mo", "piege_convinteger_int8_refuse_par_ort_1_20",
     "shares_data_with", "le paquet INT8 est ce qui a revele le refus de ConvInteger"),
    ("var_modele_quatre_tetes_int8_129mo", "regle_seuils_tajwid_lire_les_deux_formats",
     "shares_data_with", "le nouveau paquet livre les seuils dans un format different"),
    ("piege_yeh_barree_warsh_lettre_prise_pour_un_diacritique",
     "regle_hafs_par_mp3quran_warsh_par_everyayah",
     "shares_data_with", "les deux portent sur ce que le Warsh a de structurellement different du Hafs"),
    ("piege_fusionner_le_graphe_en_choisissant_un_cote",
     "regle_hafs_par_mp3quran_warsh_par_everyayah",
     "shares_data_with", "meme fusion : le graphe et la liste des recitateurs ont ete resolus par union"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step34.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, {len(g['links'])} aretes")


if __name__ == "__main__":
    main()
