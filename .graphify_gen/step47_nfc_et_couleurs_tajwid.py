#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Le decompose contre le precompose, et trois defauts de couleur."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("piege_comparer_de_l_arabe_sans_normalisation_unicode",
     "[PIEGE] Comparer deux ecritures arabes sans normalisation Unicode -- 818 bonnes entrees jetees",
     "REGRESSION INTRODUITE PUIS CORRIGEE LE MEME JOUR (2026-09-05). Le filtre "
     "des entrees amputees de `word_tokens.json` comparait les chaines "
     "caractere par caractere. Or le texte du Coran ecrit le madd en DECOMPOSE "
     "(U+0627 U+0653, alef + maddah) tandis que le vocabulaire du modele n'a "
     "AUCUNE piece portant cette sequence (0 sur 1024) et 22 portant la forme "
     "PRECOMPOSEE U+0622. Le dictionnaire donnait donc pour `مَآ` l'unique "
     "piece `▁مَآ`, parfaite pour le modele mais differente octet a octet de "
     "la cle. MESURE : 818 des 2 806 entrees ecartees (29,2 %) etaient dans ce "
     "cas ; le repli glouton leur fabriquait une cible en pieces SEPAREES "
     "(`م + َ + ا + ٓ`) que le modele ne produit jamais, et le chemin contraint "
     "s'effondrait sur des mots parfaitement recites -- `مَآ` et `يَدَآ` "
     "restaient rouges. Apres correction (comparaison en NFC) : 1 988 ecartees, "
     "verifie sur device, et les deux mots repassent verts avec gop -0,02 et "
     "0,00. REGLE : toute comparaison de deux ecritures arabes venant de "
     "sources differentes passe par NFC."),

    ("mesure_les_quatre_regles_du_texte_faisaient_des_verts_sans_jugement",
     "[MESURE] Les quatre regles « portees par le texte » fabriquaient des verts sans aucun jugement",
     "Defaut signale le 2026-09-05 : « il y a des mots en vert alors qu'ils ne "
     "portent pas de regle de tajwid ; les vraies regles ne comptent pas, "
     "laam_shamsiyah... les 4 ignorees ». Elles sont bien QUATRE "
     "(`porteesParLeTexte`) : madda_normal, laam_shamsiyah, ham_wasl, slnt. "
     "Elles sont ATTENDUES et ACTIVES dans le preset, mais `unrealizedRulesFor` "
     "les ecarte -- aucune preuve acoustique n'est possible. Un mot dont la "
     "seule regle attendue etait l'une d'elles sortait donc avec `manquantes` "
     "vide et passait VERT : le vert disait « regle reussie » alors qu'aucune "
     "regle n'avait ete jugee. Corrige en exigeant qu'au moins une regle "
     "JUGEABLE ait ete attendue -- meme filtre que pour le violet. REGLE "
     "GENERALE : ce qui ne peut pas faire un violet ne peut pas faire un vert."),

    ("regle_madda_normal_redevient_jugeable_via_le_groupe",
     "[REGLE] `madda_normal` redevient jugeable -- 8 567 occurrences, 4 423 mots ou elle est seule",
     "Demande utilisateur du 2026-09-05, apres avoir vu `وَٱمْرَأَتُهُۥ` sans "
     "couleur : « madd normal, tu peux le compter » puis, le mot revenant, "
     "« مراتهو, il y a un madd ». Le journal lui donnait raison : "
     "attendues=madda_normal, detectees=madda_obligatory,ghunnah -- "
     "l'allongement AVAIT ete entendu, seule la table des noms l'empechait de "
     "compter. Elle etait classee « portee par le texte » parce que le modele "
     "ne produit jamais ce nom-la (il nomme les madd par leur DUREE) ; mais les "
     "quatre madd sont interchangeables depuis le meme jour, donc n'importe "
     "quel madd detecte la satisfait. AMPLEUR A SURVEILLER : 8 567 occurrences "
     "dans le texte annote, dont 4 423 mots ou c'est la SEULE regle (9,7 % des "
     "mots porteurs). Ces mots passent de « jamais colores » a « juges » -- "
     "c'est le changement le plus large de la journee, et le premier a "
     "reexaminer si des violets apparaissent sur une recitation correcte."),

    ("regle_la_regle_de_jonction_colore_les_deux_mots",
     "[REGLE] Une regle de jonction colore le mot suivant, qui HERITE sans etre juge",
     "Demande utilisateur : « ذَاتَ aussi, mais je pense c'est en lien avec "
     "نَارًا -- il faut colorier ». Exact : l'ikhafa de `نَارًا ذَاتَ` se joue "
     "sur la FIN du premier mot et le DEBUT du second, mais le texte annote ne "
     "la porte que sur le premier ; le second restait sans regle attendue, donc "
     "sans couleur, alors qu'il est la moitie du phenomene juge. "
     "`isBoundaryWord` sait deja repondre -- il sert depuis le 2026-07-22 a "
     "montrer la PAIRE dans la fiche d'erreur. Le voisin HERITE de la couleur "
     "et n'est PAS juge : il n'entre pas dans le compte des etoiles, sinon une "
     "regle vaudrait double des qu'elle se voit sur deux mots."),

    ("regle_la_lecture_tajwid_juge_sur_une_seule_observation",
     "[REGLE] En lecture tajwid, une seule observation suffit -- la fenetre n'a qu'un tour",
     "Defaut signale : « مَآ n'est ni vert ni violet ». Le journal le "
     "confirme -- `tajwidFiable=false`, `frames=1` : un mot de trois lettres "
     "n'a ete vu qu'UNE fois, et le controle tajwid exige DEUX observations "
     "avant de conclure. Ni preuve que la regle manque, ni preuve qu'elle est "
     "faite : le mot restait sans couleur, et rien a l'ecran ne disait "
     "pourquoi. MEME ARGUMENT QUE LE COACH, qui leve deja cette exigence sur "
     "ses paliers : on ne repasse pas. Le prix est connu et mesure "
     "(2026-07-23) -- une regle coupee au bord d'une fenetre disparait, donc "
     "une part de faux signalements ; la note qui l'accompagne disait "
     "« acceptable la ou ca se rejoue, jamais en recitation ou le verdict est "
     "definitif », et la lecture tajwid est du premier cote : elle ne compte "
     "dans AUCUNE statistique depuis v353."),

    ("mesure_way2quran_sans_minutage_mp3quran_en_a_115",
     "[MESURE] way2quran n'a aucun minutage ; mp3quran en publie pour 115 moshafs sur 288",
     "Exploration du 2026-09-05, demandee par l'utilisateur (« way2quran "
     "dispose de beaucoup de ressources, je veux en tester quelques-uns qui ne "
     "sont pas proposes par mp3quran »). SON CDN MARCHE : "
     "`media.way2quran.com/<slug>/hafs-an-asim/<SSS>.mp3`, verifie 8/8 sur "
     "trois recitateurs bel et bien absents de mp3quran (ahmed-kaseb, "
     "haitham-al-dukhin, youssef-al-aidarous). MAIS il ne publie AUCUN minutage "
     "par verset -- or jouer un verset, suivre et corriger un mot en dependent "
     "tous. Chaque recitateur y demanderait de produire ces minutages hors app "
     "par alignement force, 114 sourates a la fois. "
     "A LA PLACE, mesure sur la source DEJA branchee : `ayat_timing` repond "
     "pour 115 des 288 moshafs de mp3quran, dont 113 au Coran complet -- "
     "5 mujawwad, 5 warsh, 3 qalon, 1 ad-duri. Ce qui manquait etait deja "
     "accessible avec les minutages. ⚠️ DEUX PIEGES FERMES en les branchant : "
     "le cache de minutage n'etait cle que par SOURATE (le minutage du premier "
     "recitateur aurait ete rejoue sur l'audio du second), et "
     "`word_segments_mp3quran_afasy.json` a ete calcule sur l'enregistrement "
     "d'Al-Afasy -- applique a une autre voix il ferait jouer un extrait pris "
     "au mauvais endroit, en silence."),
]

LIENS = [
    ("piege_comparer_de_l_arabe_sans_normalisation_unicode",
     "mesure_word_tokens_ampute_un_mot_sur_sept", "shares_data_with",
     "la regression et le correctif qu'elle a abime"),
    ("regle_madda_normal_redevient_jugeable_via_le_groupe",
     "mesure_madda_normal_manquait_au_groupe_des_madd", "shares_data_with",
     "deux moities de la meme question sur le madd naturel"),
    ("mesure_les_quatre_regles_du_texte_faisaient_des_verts_sans_jugement",
     "regle_madda_normal_redevient_jugeable_via_le_groupe", "shares_data_with",
     "les quatre regles non jugees, dont l'une est sortie"),
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
            print("  = deja present : " + nid)
            continue
        g["nodes"].append({
            "label": label, "rationale": rationale, "node_type": "concept",
            "id": nid, "community": 0, "norm_label": label.lower()})
        a += 1
    connus = {n["id"] for n in g["nodes"]}
    ar = 0
    for s, t, rel, pq in LIENS:
        if s not in connus or t not in connus:
            print("  ! cible absente : " + s + " -> " + t)
            continue
        g["links"].append({"source": s, "target": t, "relation_type": rel,
                           "source_location": pq, "rationale": pq})
        ar += 1
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step47.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print("+{} noeuds, +{} aretes -> {} noeuds, {} aretes".format(
        a, ar, len(g["nodes"]), len(g["links"])))


if __name__ == "__main__":
    main()
