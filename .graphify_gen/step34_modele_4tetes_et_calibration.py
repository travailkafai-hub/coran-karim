#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Le modele a quatre tetes : ce qui a ete mesure en l integrant.

Mesures du 2026-08-21, journaux de sessions live sur device (v174 a v178) et
rejeu hors telephone du WAV de session sur le modele INT8.
"""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("piege_conv_integer_int8_refuse_par_ort_ancien",
     "[PIEGE] Quantification INT8 a poids SIGNES : ConvInteger refuse par ORT < 1.26 sur Android",
     "Le modele est trouve, lu, puis REFUSE a la compilation du graphe : "
     "`ORT_NOT_IMPLEMENTED - Could not find an implementation for "
     "ConvInteger(10) node with name node_conv2d_quant`. Inspection du fichier : "
     "61 `ConvInteger` a poids INT8 (elem_type=3) et 205 `MatMulInteger`. Le "
     "noyau CPU de ConvInteger n'etait enregistre qu'en UINT8 jusqu'apres ORT "
     "1.20 -- d'ou des MatMul qui passent et des Conv qui bloquent, sur le MEME "
     "fichier. VERIFIE : le meme modele tourne sous onnxruntime 1.26.0 et rend "
     "ses quatre sorties finies. Correctif retenu : montee "
     "`onnxruntime-android` 1.20 -> 1.26. Correctif cote export, confirme par "
     "l'agent d'entrainement : `weight_type=QUInt8` produit un graphe sans "
     "aucun ConvInteger, pour 2,52 % de WER contre 2,35-2,37 % en QInt8 -- "
     "meme ordre de grandeur, et plus aucune contrainte de version d'ORT."),

    ("mesure_gop_change_d_echelle_avec_le_modele",
     "[MESURE] Un GOP n'a pas d'echelle absolue : changer de modele deplace toute la distribution",
     "Comparaison sur les journaux du device, ancien modele (3 tetes) contre "
     "nouveau (4 tetes), a recitation comparable : non-verts 19,0 % (11 215 / "
     "58 975 verdicts) -> 47,3 % (509 / 1 077) ; mediane du gop 0,00 -> -0,63 ; "
     "p10 -3,30 -> -13,59, soit un facteur 4. Les seuils constants "
     "(correct=-0,45, unclear=-1,60) appartiennent a l'ancien modele. "
     "CONTRE-EPREUVE qui montre que ce n'est PAS la reconnaissance qui se "
     "degrade : la part de non-verts dont le squelette entendu est EXACTEMENT "
     "l'attendu ne bouge quasiment pas (15,6 % -> 19,1 %). Quand le modele "
     "entend juste, il entend juste aussi souvent qu'avant -- c'est la regle de "
     "DECISION qui a vieilli, pas la perception."),

    ("mesure_46pct_des_non_verts_ne_sont_pas_des_fautes",
     "[MESURE] 46 % des non-verts du nouveau modele ne sont pas des fautes de recitation",
     "Decomposition des 509 non-verts du nouveau modele par comparaison du "
     "squelette entendu a l'attendu : squelette EXACTEMENT egal 97 (19,1 %), "
     "FRAGMENT du mot 114 (22,4 %), DOUBLEMENT de lettres ou diacritiques 25 "
     "(4,9 %), rien entendu 8 (1,6 %), autre 265 (52,1 %). Les trois premieres "
     "categories -- 46 % du total -- ne disent rien de la facon dont "
     "l'utilisateur a recite. Le plus gros bloc n'est pas le seuil mais les "
     "FRAGMENTS : un mot qui ne recoit qu'une ou deux trames ne peut pas obtenir "
     "un bon gop, quel que soit le seuil."),

    ("mesure_doublements_viennent_du_fenetrage_pas_du_modele",
     "[MESURE] Les doublements (`ٱل ٱل`, `دِِّّ`) viennent du FENETRAGE, pas du modele",
     "Le meme WAV de session (37,5 s) rejoue HORS TELEPHONE en UNE SEULE PASSE "
     "sur le modele INT8 rend `ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ...` sans un seul "
     "doublement, alors que la chaine v2 avait produit `ٱل ٱلرَّحْمَّحْمَـٰنِ` et "
     "`ٱلدِِّّيينِ` sur le meme audio. Un decodage en une passe n'a pas de fenetres "
     "qui se recouvrent ; la chaine, si. Le modele n'invente donc rien : c'est "
     "la fusion des fenetres qui recolle deux fois le meme bout d'audio. "
     "Frequence mesuree sur les journaux : 2,2 % des mots entendus sous "
     "l'ancien modele, 4,5 % sous le nouveau -- defaut PREEXISTANT, deux fois "
     "plus frequent, mais trop rare pour expliquer les 28 points de non-verts "
     "supplementaires. Duree de trame verifiee au passage : 470 trames pour "
     "37,5 s = 79,8 ms, conforme aux 80 ms supposees par l'app."),

    ("mesure_tete_warsh_produit_bien_de_l_orthographe_warsh",
     "[MESURE] La tete Warsh (sortie 2) produit bien du Warsh, pas du Hafs deguise",
     "Rejeu du WAV de session sur la sortie 2 avec `vocab_warsh.json` : "
     "`اِ۬لْحَمْدُ لِلهِ رَبِّ اِ۬لْعَٰلَمِينَ مَلِكِ يَوْمَ ...` -- `مَلِكِ` (lecture Warsh) contre "
     "`مَـٰلِكِ` (Hafs), et `لِلهِ` sans alif suscrit. La sortie est exploitable telle "
     "quelle. ⚠️ La bascule ne peut PAS se limiter a l'index de sortie : "
     "mesure du meme jour, 1009 pieces sur 1024 different entre `vocab.json` et "
     "`vocab_warsh.json`. Detokeniser la sortie Warsh avec le vocabulaire Hafs "
     "rendrait du charabia, et l'alignement force TOKENISERAIT la cible Warsh "
     "avec des pieces Hafs."),

    ("piege_calibrations_attachees_a_un_modele_et_a_une_riwaya",
     "[PIEGE] Toute calibration est attachee A UN MODELE, et ici AUSSI a une riwaya",
     "Trois fichiers de calibration accompagnent le modele et ne valent que "
     "pour lui : `tete3.json` (le README chiffre 91,1 % -> 14,4 % de detection "
     "quand on applique les poids d'un autre encodeur, SANS lever d'erreur), "
     "`seuils_tajwid.json`, et les seuils de gop. VERIFIE par l'agent "
     "d'entrainement le 2026-08-21 : `grep -c warsh` rend 0 sur les DEUX corpus "
     "sources (`train_manifest_final.jsonl`, 201 956 lignes ; "
     "`tajwid_frames_v6.jsonl`, 45 recitateurs). La tete 3 et les seuils tajwid "
     "sont donc calibres sur du Hafs PUR : l'etat encodeur transfere "
     "probablement (encodeur partage) mais les 12 scores dependent de "
     "l'alignement force contre le texte, avec un tokenizer. Ne pas les brancher "
     "sur du Warsh sans calibration separee."),

    ("mort_gop_word_baseline_charge_mais_jamais_branche",
     "[MORT] `gop_word_baseline.json` : 1,97 Mo charges a chaque demarrage, branches NULLE PART",
     "Le fichier existe (42 927 clips, construit le 2026-07-20), un provider le "
     "charge (`gopBaselineProvider`), et sa doc explique en detail pourquoi "
     "recentrer le gop par mot -- `مِّنَ` tombe a -7,58 en moyenne sur des "
     "recitations professionnelles verifiees. Mais `grep` sur "
     "`gopBaselineProvider|GopWordBaseline` hors de son propre fichier ne rend "
     "RIEN : le recentrage n'a jamais ete cable. Consequence directe : le "
     "changement d'echelle du gop entre deux modeles n'est absorbe par rien. "
     "⚠️ Erreur d'analyse commise puis corrigee le meme jour : j'ai d'abord "
     "explique les regressions par ce recentrage \"calibre en juillet\", avant "
     "de verifier qu'il n'a jamais tourne. Une explication plausible n'est pas "
     "une preuve."),

    ("regle_madd_long_et_madd_court_par_comparaison",
     "[REGLE] `madd_long` / `madd_court` se decident par COMPARAISON, et regroupent 4 anciens noms",
     "Table fournie par l'agent d'entrainement, issue de "
     "`build_frame_level_tajwid_labels.py` (2026-08-04) : `madd_long` = "
     "madda_necessary + madda_obligatory + madda_permissible ; `madd_court` = "
     "madda_normal. Ce n'est pas un raccourci technique : `madda_obligatory` et "
     "`madda_permissible` ont la MEME duree (4-5 harakat), ce qui les distingue "
     "est ce qui SUIT la voyelle -- une categorie grammaticale que le texte "
     "connait deja et que l'acoustique ne peut pas trancher. Cas reel cite : le "
     "mot `إِلَّآ` etait signale \"madda_obligatory non detectee\" alors que la tete "
     "detectait `madda_permissible` au meme endroit -- l'app accusait a tort un "
     "madd qui etait fait. Au DECODAGE, les deux classes ne se seuillent pas "
     "separement : le plus grand des deux gagne, trame par trame (un madd court "
     "prononce la ou un long est attendu sort `madd_long` a 0,538 ET "
     "`madd_court` a 0,952 ; `madd_long` seul affiche 42,4 % d'invention)."),

    ("piege_ecran_qui_decide_sur_une_calibration_jamais_verifiee",
     "[EN ATTENTE] La tete 3 ne tranche aucun verdict, et sa parite n'a jamais ete verifiee",
     "`Tete3.verifierParite` existe et sa doc pose la condition : \"TANT "
     "QU'ELLE N'A PAS ETE PASSEE SUR DEVICE, la sortie de cette tete ne doit PAS "
     "trancher un verdict\". Verifie le 2026-08-21 : la fonction n'est appelee "
     "NULLE PART, et `Decideur.kt` ne mentionne ni la tete 3 ni son logit -- la "
     "condition est donc respectee, la tete est calculee et journalisee "
     "(`[t3] mot=N logit=...`) sans rien decider. Ce qui BLOQUE la levee de "
     "cette condition : le `tete3.json` livre ne contient aucun vecteur de "
     "reference (cles : description, caracteristiques, normalisation, couches), "
     "donc la parite Python/Kotlin n'est pas verifiable cote app. C'est une "
     "demande a formuler, pas une tache executable ici. Rappel du cout : les "
     "memes poids sur un autre encodeur donnent 14,4 % au lieu de 91,1 %, sans "
     "aucune erreur levee."),
]

LIENS = [
    ("mesure_gop_change_d_echelle_avec_le_modele",
     "mort_gop_word_baseline_charge_mais_jamais_branche", "shares_data_with",
     "le recentrage par mot aurait pu absorber le changement d'echelle -- il n'a jamais tourne"),
    ("mesure_46pct_des_non_verts_ne_sont_pas_des_fautes",
     "mesure_doublements_viennent_du_fenetrage_pas_du_modele", "shares_data_with",
     "fragments et doublements font 27 % des non-verts, et viennent du meme endroit"),
    ("mesure_46pct_des_non_verts_ne_sont_pas_des_fautes",
     "mesure_gop_change_d_echelle_avec_le_modele", "shares_data_with",
     "deux causes distinctes du meme symptome : le fenetrage et la regle de decision"),
    ("piege_calibrations_attachees_a_un_modele_et_a_une_riwaya",
     "mesure_gop_change_d_echelle_avec_le_modele", "shares_data_with",
     "meme famille : une reference mesuree ailleurs, appliquee ici sans le dire"),
    ("mesure_tete_warsh_produit_bien_de_l_orthographe_warsh",
     "piege_calibrations_attachees_a_un_modele_et_a_une_riwaya", "shares_data_with",
     "la tete Warsh marche, mais aucune de ses calibrations n'a vu de Warsh"),
    ("piege_conv_integer_int8_refuse_par_ort_ancien",
     "piege_v2activer_avant_chargement_du_modele", "shares_data_with",
     "deux facons pour un modele present de ne pas juger : refuse a la compilation, ou jamais active"),
    ("regle_madd_long_et_madd_court_par_comparaison",
     "mort_seuil_plat_0_5_tete_tajwid", "shares_data_with",
     "meme lecon : un seuil par classe ne suffit pas quand deux classes repondent a la meme question"),
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
