#!/usr/bin/env python3
"""Bascule Warsh : mesures du 2026-08-12 (branche chantier-warsh)."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_warsh_rasm_identique_a_99_pourcent",
     "[MESURE] Hafs et Warsh : 77 429 mots contre 77 427, squelette identique a 99,16 %, mais 37,88 % different UNE FOIS LES HARAKAT COMPTEES",
     "Comparaison exhaustive du 2026-08-12 entre l'asset Hafs de l'app et le "
     "texte KFGQPC Warsh (6 214 versets). Deux mots d'ecart sur tout le Coran ; "
     "649 mots (0,84 %) divergent vraiment au squelette consonantique. MAIS le "
     "tokenizer du modele est un BPE tajweed qui CONSERVE les diacritiques, et "
     "a ce niveau seuls 62,12 % des mots sont identiques. Ce couple de chiffres "
     "est la prediction a confronter au terrain : le modele devrait retrouver "
     "les bons MOTS (donc s'ancrer et aligner) tout en signalant beaucoup de "
     "PRONONCIATIONS -- c'est justement la vocalisation qui change d'une riwaya "
     "a l'autre. Piege de methode paye au passage : sans mapper le YEH BARREE "
     "et l'ALEF WASLA, on mesure son propre normaliseur (6,25 % d'ecart) et non "
     "les deux textes (0,84 %)."),

    ("regle_yeh_barree_lettre_et_non_diacritique",
     "[REGLE] Le YEH BARREE (U+06D2) du script Warsh est une LETTRE : sans mapping, 2 921 mots rouges quoi que recite l'utilisateur (94,29 % -> 98,06 %)",
     "Le mushaf Warsh ecrit le ya final avec U+06D2 (2 996 occurrences) : "
     "فے، الذے، شےء. La classe `_harakat` d'ArabicNormalizer couvre bien les "
     "diacritiques propres au Warsh (U+0655 a U+0657, U+065E, tous dans la "
     "plage U+064B-U+0670), mais U+06D2 est une lettre : il survivait. Mesure "
     "du 2026-08-12 sur le texte entier : la part des mots Warsh dont le "
     "squelette correspond a ce que le modele peut ecrire passe de 94,29 % a "
     "98,06 %, soit 2 921 mots sauves. ZERO RISQUE COTE HAFS, prouve par "
     "comptage et non par opinion : ce caractere apparait 0 fois dans le texte "
     "Hafs, 0 fois dans les 1 024 tokens du vocabulaire, 0 fois dans les "
     "19 001 mots de word_tokens.json -- le modele ne peut structurellement "
     "jamais le produire. Controle exhaustif : 0 des 6 236 versets Hafs voit "
     "sa normalisation changer."),

    ("regle_riwaya_point_de_bascule_unique",
     "[REGLE] Une seule variable (Riwaya, portee par QuranApi avec son cache) commande texte, recherche, recitateur et audio de correction",
     "Le reglage vit sur `QuranApi` -- la ou vit le CACHE du texte -- et non "
     "dans un provider : appele depuis des services sans `Ref`, et surtout un "
     "reglage separe du cache qu'il invalide laisse un ecran lire l'ancien "
     "texte apres bascule. Les deux assets partagent les MEMES cles de verset "
     "(cf. le noeud everyayah), donc portions, statistiques, signets et records "
     "suivent sans une ligne de code. Partout ou le Warsh exige un autre chemin "
     "(URL audio, timings, liste de recitateurs), la branche Warsh sort AVANT "
     "le code Hafs, qui reste mot pour mot celui d'hier : la non-regression est "
     "structurelle, pas testee apres coup. Le locateur retient QUELLE riwaya son "
     "index porte -- sans quoi il aurait cherche dans l'autre lecture en "
     "trouvant quand meme le bon verset la plupart du temps (97,42 % des mots "
     "normalises communs), c'est-a-dire une panne partielle et silencieuse."),

    ("mesure_everyayah_audio_warsh_en_numerotation_hafs",
     "[MESURE] L'audio Warsh d'everyayah est indexe sur les MEMES numeros de verset que l'app -- ce qui evite toute migration de donnees",
     "Verifie le 2026-08-12 par requetes reelles : deux recitateurs Warsh "
     "complets (Ibrahim Al-Dosary 128k, Yassin Al-Jazaery 64k), couverture 9/9 "
     "sur le dernier verset des sourates 1, 2, 3, 18, 36, 55, 78, 110, 114. Or "
     "`002286.mp3` EXISTE et dure 75,8 s alors que le mushaf Warsh imprime "
     "s'arrete a 285 versets : la numerotation est celle du mushaf du Caire. "
     "C'est ce fait qui a decide la construction de l'asset texte -- le texte "
     "Warsh y est recoupe sur les memes frontieres de verset, sinon plus aucun "
     "fichier audio ne tomberait en face de son texte. L'API quran.com est un "
     "cul-de-sac verifie : son parametre de script est ignore (meme un "
     "identifiant invente renvoie le texte Hafs, HTTP 200) et ses 12 "
     "recitateurs sont tous Hafs."),

    ("limite_timings_mot_a_mot_estimes_en_warsh",
     "[MESURE] Aucune source ne publie de timings mot-a-mot en Warsh : la decoupe y est ESTIMEE (ponderee par la longueur des mots) et le journal le dit",
     "quran.com ne publie de segments que pour ses propres recitateurs, tous "
     "Hafs. Sans eux la correction Warsh serait purement muette -- or c'est la "
     "fonction meme demandee (« en cas d'erreur, la prononciation Warsh »). La "
     "decoupe est donc estimee sur la duree reelle du fichier, ponderee par le "
     "nombre de lettres de chaque mot : un partage a parts egales mettrait "
     "وَٱلَّذِينَ et مَا sur la meme duree et l'erreur s'accumulerait jusqu'a la fin "
     "du verset. Chaque estimation ecrit `timings ESTIMES (Warsh)` dans le "
     "journal : une estimation prise pour une mesure est un piege, une "
     "estimation nommee est un point de depart mesurable. A remplacer par "
     "l'aligneur force du modele, qui est l'outil exact pour produire ces "
     "timings."),
]

LIENS = [
    ("regle_yeh_barree_lettre_et_non_diacritique", "mesure_warsh_rasm_identique_a_99_pourcent",
     "s_appuie_sur", "l'ecart apparent venait du normaliseur, pas des deux textes"),
    ("regle_riwaya_point_de_bascule_unique", "mesure_everyayah_audio_warsh_en_numerotation_hafs",
     "s_appuie_sur", "les cles de verset partagees sont ce qui rend la bascule sans migration"),
    ("limite_timings_mot_a_mot_estimes_en_warsh", "regle_riwaya_point_de_bascule_unique",
     "limite", "seul point ou le Warsh est moins precis que le Hafs, nomme comme tel"),
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
            continue
        g["nodes"].append({
            "label": label, "file_type": "concept",
            "source_file": "app/lib/services/recitation_verifier.dart",
            "source_location": None, "source_url": None,
            "captured_at": "2026-08-12", "author": None, "contributor": None,
            "rationale": rationale, "_origin": "semantic",
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step30.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, {len(g['links'])} aretes")


if __name__ == "__main__":
    main()
