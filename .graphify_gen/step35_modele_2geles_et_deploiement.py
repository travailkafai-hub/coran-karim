#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Le modele a deux tetes gelees (tajwid v2) : ce qui a ete mesure en l integrant.

Mesures du 2026-08-22 : rejeu hors telephone des modeles INT8 sur un vrai mel
(Al-Afasy), journaux device v179/v180, et deploiement sur deux appareils.
"""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_modele_22aout_change_l_encodeur",
     "[MESURE] Le modele du 22 aout change l'encodeur, malgre le \"deux geles\" de son nom",
     "Rejeu des deux modeles INT8 sur le MEME mel (Al-Afasy 112:1, mel facon "
     "NeMo, les deux decodent correctement le texte -- donc la comparaison est "
     "recevable, contrairement a un premier essai sur bruit gaussien hors "
     "distribution qui n'a rien prouve). Ecart moyen sur encoder_state 0,557 "
     "pour un ecart-type de 0,585 (ratio 0,95) ; cosinus entre les deux etats "
     "MOYENS 0,8834. Ce n'est pas du bruit de quantification. GAIN VISIBLE cote "
     "Warsh sur le meme audio : l'ancien rendait le mot tronque, le nouveau le "
     "mot entier. CONSEQUENCE : des poids de tete 3 calibres sur l'encodeur du "
     "21 ne valent rien ici -- le README du paquet chiffre ce cout a 91,1 % -> "
     "14,4 % de detection, sans qu'une seule exception soit levee."),

    ("mesure_deux_moutures_du_22_seule_la_tete_tajwid_change",
     "[MESURE] Entre les deux moutures du 22 aout, SEULE la tete tajwid change",
     "Deux fichiers model_int8.onnx de taille IDENTIQUE (134 595 380 o) et "
     "d'empreinte differente : 0358d5f1 (depose sur l'appareil a 12:25, avec "
     "tete3.json) et 47f05043 (livre a 17:00, avec seuils_tajwid.json). "
     "Compares sur le meme mel : encoder_state ecart 0,00000 et cosinus "
     "1,000000 ; logprobs (Hafs) 0,00000 ; warsh_logprobs 0,00000 ; "
     "tajwid_logprobs est LA SEULE sortie qui bouge (ratio 0,638). C'est le "
     "\"tajwid2\" du nom. CONSEQUENCE UTILE : la tete 3 livree avec la mouture "
     "de 12:25 est valide sur celle de 17:00 -- prouve, pas suppose. Le paquet "
     "deploye combine donc modele et seuils du 17:00 avec la tete 3 du 12:25."),

    ("mesure_ordre_des_17_classes_tajwid_verifie",
     "[MESURE] L'ordre des 17 classes tajwid est verifie sur un verset a regles connues",
     "rules.json a ete repris du paquet du 21 (la livraison du 22 ne le porte "
     "pas). Plutot que supposer l'ordre, controle sur la Bismillah : ham_wasl "
     "sort a p=0,892 et rend EXACTEMENT 3 trames retenues, or le verset porte "
     "exactement trois hamzat wasl ; laam_shamsiyah -- l'autre regle certaine "
     "-- est la deuxieme probabilite la plus forte (0,889) ; les classes "
     "inapplicables (idgham_mutaqaribayn, waqf_lazim, waqf_awla) sont a 0,000. "
     "Une correspondance 3/3 sur la classe la plus active ne peut pas etre "
     "fortuite. OBSERVATION AU PASSAGE : le seuil de laam_shamsiyah (0,95) "
     "recale une regle vue a 0,889 -- a rejouer sur ce modele."),

    ("piege_fichier_de_seuils_dans_une_forme_non_lue",
     "[PIEGE] Un fichier de seuils livre dans une TROISIEME forme est ignore sans un mot",
     "Le parseur ne lisait que deux formes : sous la cle `seuils` (3 tetes) ou "
     "sous `regles` (4 tetes). La livraison du 22 porte les 17 seuils A LA "
     "RACINE du JSON. Les deux lectures rendaient null, et le repli portait les "
     "17 classes a ln(0,5) SANS UNE LIGNE DE JOURNAL -- soit exactement le "
     "seuil plat que ce fichier existe pour remplacer, mesure a +209 % de "
     "sur-detection sur la fenetre de calibrage et +240 % hors fenetre. Un "
     "fichier livre, lu, et sans effet se lit comme un succes : c'est la pire "
     "des trois situations. CORRECTIF : les trois formes sont acceptees, et la "
     "forme retenue est JOURNALISEE avec le nombre de classes reellement "
     "servies. Verifie a l'execution : `seuils tajwid : forme=plat a la racine "
     "classes=17 servies=17`."),

    ("piege_storage_externe_ls_le_voit_dart_non",
     "[PIEGE] Modele pousse dans le storage EXTERNE : ls le voit, Dart repond existe=false",
     "Modele pousse par adb dans /sdcard/Android/data/<pkg>/files/models/, "
     "liste par ls, permissions rw-rw-rw- -- et le journal dit "
     "`verif storage externe : ... existe=false` puis `model.onnx, vocab.json "
     "introuvable dans /data/user/0/...`. Le dossier models/ cree par `adb "
     "shell mkdir` appartient a `shell`, alors que files/ appartient a l'app "
     "(u0_a720). Le symptome etait deja decrit dans fastconformer_verifier.dart "
     "(2026-08-13) sans cause identifiee. ROUTE QUI FONCTIONNE : adb push vers "
     "/data/local/tmp/, puis `run-as <pkg> cp` vers files/models/<paquet>/ -- "
     "verifie sur deux appareils."),

    ("piege_adb_shell_cat_corrompt_un_binaire",
     "[PIEGE] `adb shell cat` corrompt un binaire : empreinte fausse, mesure attribuee au mauvais fichier",
     "Sur le meme model.onnx de 134 Mo, trois methodes ont rendu trois "
     "empreintes : `adb shell cat | md5sum` -> 89690ce6, `adb exec-out cat` -> "
     "0358d5f1, et le calcul FAIT SUR LE TELEPHONE (`run-as toybox md5sum`) -> "
     "0358d5f1. C'est donc `adb shell cat` qui altere le flux ; exec-out est "
     "fidele. Une empreinte fausse sur un modele, c'est une mesure attribuee au "
     "mauvais fichier -- exactement ce que le projet a paye avec v8 mesure sous "
     "l'etiquette v23. REGLE : verifier une empreinte SUR l'appareil, ou via "
     "exec-out, jamais via adb shell cat."),

    ("piege_telephone_verrouille_autodemarrer_ne_prend_pas",
     "[PIEGE] Telephone verrouille : autoDemarrer ne prend pas, et le journal reste muet",
     "Le banc lance l'ecran de recitation, la capture d'ecran montre bien la "
     "cible 2:1 -> 2:20 -- et l'ecran reste sur \"Touche l'ecran pour "
     "commencer\". Le journal s'arrete juste apres \"fichier natif relie\", "
     "sans une seule ligne d'erreur. Cause : `dumpsys window` donne "
     "mDreamingLockscreen=true ; autoDemarrer ne prend pas derriere l'ecran de "
     "verrouillage. Le silence se lit alors comme un probleme de MODELE, ce qui "
     "envoie chercher au mauvais endroit. CORRECTIF dans recette_1tel_v2.sh : "
     "`input keyevent KEYCODE_WAKEUP` + `wm dismiss-keyguard` avant le "
     "lancement, sans effet si l'appareil est deja reveille."),

    ("piege_nom_de_dossier_modele_a_un_tiret_pres",
     "[PIEGE] Un nom de dossier de modele faux d'un tiret : \"introuvable\" qu'on lit comme un probleme de droits",
     "La constante pointait `models/deux-geles-2026-08-22` alors que le paquet "
     "depose s'appelle `deux-geles-int8-2026-08-22`. Le journal le dit "
     "correctement (`model.onnx, vocab.json introuvable dans ...`), mais avec "
     "un probleme de storage externe actif EN MEME TEMPS, le message a d'abord "
     "ete lu comme une question de permissions. Deux causes distinctes "
     "produisant le meme symptome : chacune doit etre eliminee separement, en "
     "comparant le nom EXACT du dossier present sur l'appareil."),
]

LIENS = [
    ("mesure_deux_moutures_du_22_seule_la_tete_tajwid_change",
     "mesure_modele_22aout_change_l_encodeur", "shares_data_with",
     "meme instrument : comparer les sorties sur un mel identique dit ce qui a bouge"),
    ("piege_fichier_de_seuils_dans_une_forme_non_lue",
     "mort_seuil_plat_0_5_tete_tajwid", "shares_data_with",
     "le repli silencieux ramene exactement le seuil plat deja mesure perdant"),
    ("piege_adb_shell_cat_corrompt_un_binaire",
     "piege_storage_externe_ls_le_voit_dart_non", "shares_data_with",
     "deux facons de croire un modele en place alors qu'il ne l'est pas"),
    ("piege_nom_de_dossier_modele_a_un_tiret_pres",
     "piege_storage_externe_ls_le_voit_dart_non", "shares_data_with",
     "deux causes distinctes, un seul symptome : \"modele introuvable\""),
    ("mesure_ordre_des_17_classes_tajwid_verifie",
     "regle_madd_long_et_madd_court_par_comparaison", "shares_data_with",
     "meme tete, meme table de classes : l'ordre conditionne les deux"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step35.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, {len(g['links'])} aretes")


if __name__ == "__main__":
    main()
