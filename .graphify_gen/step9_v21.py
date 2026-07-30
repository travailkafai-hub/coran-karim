#!/usr/bin/env python3
"""Consigne les mesures du 2026-07-30 (v2.1) dans le graphe existant.

Meme principe que step8_v2.py : on enrichit, on n'ecrase pas, et le `rationale`
porte LE CHIFFRE -- jamais l'intention. Un noeud sans mesure ne sert a rien.

Toutes les mesures de ce fichier viennent du MEME protocole : flux brut d'une
recitation professionnelle (379,8 s, 296 mots, capte pendant la recette a deux
telephones du 2026-07-30 17:30), modele causal du telephone, banc `BancFluxBrut`
qui appelle le vrai code des couches B/D/E/F/G.
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_decoupage_silences",
     "[MESURE] Couper aux SILENCES REELS, et rien d'autre",
     "Flux brut, 296 mots, modele du telephone, SEULE la politique de decoupage "
     "change -- erreur mot du decodage libre : fichier entier 54,05 % (202 mots "
     "lus) | clips du portier RMS recolles, 44 blocs 29,05 % (269) | regroupes "
     "~18 s, 17 blocs 39,19 % (244) | COUPE AUX SILENCES REELS pause>=0,5 s, 20 "
     "blocs 14,86 % (307 mots lus), 7,43 % en lettres seules. Ce n'est PAS la "
     "longueur du bloc qui compte, c'est que ses bornes tombent la ou le "
     "recitateur se tait : un bloc delimite par des silences EST un clip "
     "d'entrainement."),
    ("piege_coupe_hors_silence",
     "[PIEGE] Toute coupe hors silence detruit l'alignement du bloc ENTIER",
     "MESURE : le garde-fou « jamais plus de 18 s » coupait en pleine parole "
     "quand le recitateur enchainait. Non-verts 51,53 % avec, 11,86 % sans -- "
     "sur le meme audio et le meme code par ailleurs. Un garde-fou de domaine "
     "qui coupe au mauvais endroit coute plus cher que le domaine qu'il protege."),
    ("piege_bande_depart_balayage",
     "[PIEGE] La bande d'alignement doit partir du premier mot ATTESTE",
     "MESURE : la bande partait du point de depart du BALAYAGE. Un bloc "
     "contenant les mots 12 a 25 se voyait reclamer les mots 0 a 25 ; la DP "
     "entassait douze mots absents sur les premieres frames et corrompait tout "
     "le bloc. Preuve, meme mot, meme session : f0 (18,00 s) mot 2 gop=0,00 "
     "entendu correct ; f2 (13,52 s) mot 2 gop=-21,84 entendu vide, bande=0..25. "
     "Les degats croissent avec la longueur du bloc : 36,61 % de non-verts en "
     "fenetres de 6 s, 80,00 % en blocs de 18 s. Regle : on ne demande a la DP "
     "QUE ce que le decodage libre atteste."),
    ("piege_bloc_sans_lookahead",
     "[PIEGE] Un bloc doit contenir le silence ENTIER, pas la moitie",
     "MESURE : en coupant au MILIEU du silence, chaque bloc ne gardait qu'une "
     "demi-pause a droite (~0,15 s) alors que le modele causal exige 1,04 s "
     "d'audio POSTERIEUR. Le dernier mot de chaque enonce etait donc toujours "
     "« au bord », jamais votant, et declare Omis ALORS QU'IL ETAIT LU "
     "PARFAITEMENT (mot 67 et mot 287 : gop=0,00, texte exact). Corrige en "
     "retardant la fermeture du bloc jusqu'a un lookahead complet apres la "
     "derniere parole : 7,12 % -> 4,07 %."),
    ("regle_deux_mesures_independantes",
     "[REGLE] Deux mesures INDEPENDANTES valent deux fenetres",
     "MESURE : exiger deux FENETRES concordantes etait une approximation de "
     "« exiger deux preuves ». Le decodage libre ignore le texte attendu, "
     "l'alignement force le connait : quand les deux concordent sur le meme "
     "audio, on tient deux preuves independantes. Le bloc de FUSION, lui, "
     "apportait une 2e preuve systematiquement DEGRADEE (mot tronque) qui "
     "detruisait l'accord. 8,14 % -> 4,41 %."),
    ("regle_pas_de_verdict_sur_entendu_vide",
     "[REGLE] Aucun verdict sur `entendu` VIDE -- pas meme un rouge",
     "MESURE : les mots 171 et 172 etaient figes ROUGE par deux blocs a "
     "`entendu` vide et `free` proche de 0 (signature de MAUVAISE POSITION, cf. "
     "piege_gop_vs_free), alors que le bloc suivant les lisait parfaitement "
     "(gop=0,00, texte exact). Un `entendu` vide veut dire que les frames "
     "attribuees n'emettent RIEN : on ne peut rien en conclure. Ce n'est pas une "
     "tolerance -- une faute de prononciation produit un AUTRE mot, pas rien. "
     "3,73 % -> 3,39 %. C'est aussi le controle BLOQUANT du superviseur, que la "
     "v1 viole 5 a 6 fois par session."),
    ("mesure_ecritures_equivalentes",
     "[MESURE] Deux graphies du meme son ne sont pas une faute",
     "MESURE : sur une recitation SANS faute, `firashan` ecrit avec un alif "
     "SUSCRIT (U+0670) etait entendu avec un alif PLEIN -> gop -0,39 a -0,48, "
     "donc orange. Les deux notent la MEME voyelle longue : rien a distinguer a "
     "l'oreille. En rescorant les graphies equivalentes sur les MEMES frames "
     "(forward CTC local) : 4,07 % -> 3,73 %. N'inclut NI les substitutions de "
     "lettres NI les harakat, qui changent le son."),
    ("mort_seuil_trois_mots_non_reconnus",
     "[MORT] Apparieur glouton qui abandonne apres 3 mots non reconnus",
     "MESURE QUI LA TUE : sur des blocs longs (~40 mots), trois substitutions "
     "groupees suffisaient a faire decrocher l'appariement -- ancre bloquee au "
     "mot 82 sur 295, 153 observations au lieu de 1440. Remplace par une LCS, "
     "qui n'a besoin d'AUCUN seuil : insertions et suppressions sont des trous "
     "du chemin, pas des motifs d'abandon."),
    ("mort_depassement_pour_figer_non_vert",
     "[MORT] Conditionner le verrouillage d'un NON-VERT au depassement de l'ancre",
     "MESURE QUI LA TUE : aucun effet (11/295 avant et apres). Avec des blocs "
     "delimites par les silences, l'ancre a TOUJOURS deja depasse le mot au "
     "moment ou il est juge. La condition est conservee (elle ne coute rien et "
     "protege le cas des blocs courts) mais elle n'explique aucun defaut."),
    ("mesure_modele_pas_le_levier",
     "[MESURE] Le modele n'est PAS le levier du jugement",
     "A decoupage identique, sur le meme flux brut : tajweed-v2_059 est le "
     "MEILLEUR en transcription (4,05 % d'erreur mot lettres) et donne 10,88 % "
     "de mots non verts ; causal-v1 deploye est a 7,77 % en transcription et "
     "donne 4,07 % de non-verts. Le decodage libre et l'alignement force ne "
     "mesurent pas la meme chose -- un bon transcripteur n'est pas "
     "automatiquement un bon juge. Tous les modeles testes : tajweed-v2_059 "
     "4,05 % | tajweed-epoch09 4,39 % | mixed-e02 5,74 % | causal-v1 7,77 % | "
     "tajweed-augmented 15,88 % | pcd_ACTUEL 14,86 % | rules-260h 67-68 %."),
    ("regle_banc_hors_telephone",
     "[REGLE] Le banc doit tourner SANS telephone, en moins d'une minute",
     "MESURE indirecte mais decisive : huit iterations mesurees dans une seule "
     "seance, contre deux quand chaque essai passait par build APK + install + "
     "intent + lecture du log (5 minutes, telephones branches). `BancFluxBrut` "
     "fait tourner la chaine v2 entiere en ~30 s sur le vrai flux brut, en "
     "APPELANT le code de l'app : les couches B/D/E/F/G n'ont aucune dependance "
     "Android ni ONNX. Seule la couche C (mel+ONNX) vient de l'exterieur, sur "
     "les blocs que la couche B a decides -- le script ne decide aucune "
     "politique."),
]

LIENS = [
    ("mesure_decoupage_silences", "couche_v2_b_fenetres", "mesure",
     "la mesure qui fixe la politique de decoupage"),
    ("mesure_decoupage_silences", "mort_coupe_chaque_pause", "reouvre",
     "[MORT] mesure en 2026-07-23 sur le modele NON CAUSAL, et dans une chaine "
     "ou couper FIGEAIT du texte. Ici une coupe ne fige rien : elle delimite une "
     "fenetre d'analyse. Cause nouvelle nommee, mesure refaite sur le modele "
     "d'aujourd'hui."),
    ("piege_coupe_hors_silence", "couche_v2_b_fenetres", "nait_dans", None),
    ("piege_bande_depart_balayage", "couche_v2_d_localisation", "nait_dans", None),
    ("piege_bloc_sans_lookahead", "couche_v2_b_fenetres", "nait_dans", None),
    ("regle_deux_mesures_independantes", "couche_v2_g_decision", "s_applique_a", None),
    ("regle_pas_de_verdict_sur_entendu_vide", "couche_v2_g_decision", "s_applique_a", None),
    ("regle_pas_de_verdict_sur_entendu_vide", "regle_preuve_acoustique", "precise",
     "le cas particulier le plus frequent : un rouge sur du vide"),
    ("regle_pas_de_verdict_sur_entendu_vide", "sympt_entendu_vide", "neutralise",
     "le symptome ne peut plus produire de verdict"),
    ("mesure_ecritures_equivalentes", "couche_v2_e_alignement", "s_applique_a", None),
    ("mesure_ecritures_equivalentes", "attente_rescoring_letter", "distinct_de",
     "graphies EQUIVALENTES (meme son) vs lettres CONFUSABLES (sons differents) "
     "-- deux buts opposes, ne pas les confondre"),
    ("mort_seuil_trois_mots_non_reconnus", "couche_v2_d_localisation", "nait_dans", None),
    ("mort_depassement_pour_figer_non_vert", "couche_v2_g_decision", "nait_dans", None),
    ("mesure_modele_pas_le_levier", "couche_v2_e_alignement", "mesure", None),
    ("regle_banc_hors_telephone", "regle_banc_appelle_le_code", "precise",
     "la contrainte de temps, sans laquelle la regle reste theorique"),
    ("piege_bloc_sans_lookahead", "attente_max_silence_09", "reprend",
     "meme direction, mais la valeur est DERIVEE (lookahead) et non reglee"),
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
            "source_file": "CONCEPTION_RECITATION_V2.md", "source_location": None,
            "source_url": None, "captured_at": "2026-07-30", "author": None,
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
        g["links"].append({
            "source": s, "target": t, "relation_type": rel,
            "source_location": pourquoi, "rationale": pourquoi,
        })
        aretes += 1

    shutil.copy2(GRAPHE, SORTIE / "graph_avant_v21.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
