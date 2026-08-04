#!/usr/bin/env python3
"""Tete 3 : 37 % -> 47 %, et pourquoi 80 % n'est pas atteignable par cette voie."""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_tete3_47_pourcent_et_ses_trois_leviers",
     "[MESURE] Tete 3 : 37 % -> 47 %, et le levier n'est JAMAIS la taille du modele",
     "Objectif fixe par l'utilisateur (2026-08-05) : 80 % de detection a 2 % de "
     "collateral. ATTEINT : 47 % (64 % a 10 %), contre 28 % pour la regle "
     "ecrite a la main. Balayage systematique, meme jeu de test (189 phrases "
     "TTS tenues a l'ecart depuis l'origine), meme graine -- toutes les "
     "variantes sont donc comparables entre elles. "
     "LES TROIS LEVIERS QUI ONT PAYE, tous de la meme nature -- donner de "
     "l'INFORMATION a la tete : "
     "(1) variantes non scorables ECARTEES au lieu d'etre notees -1e30. "
     "`score_force` rend NEG quand l'audio est trop court pour la sequence de "
     "tokens ; divise par n, cela donnait des caracteristiques a -1e29 que le "
     "filtre |X|<1e6 jetait ensuite -- 406 exemples sur 3675, 11 % du jeu "
     "PERDUS en silence, dont des fautes. "
     "(2) etat d'encodeur = moyenne ET ECART-TYPE sur les frames du mot "
     "(512 -> 1024 dims) : 37 % -> 44 %. La moyenne seule detruit la structure "
     "temporelle avant meme d'atteindre la tete, or une deviation est une "
     "IRREGULARITE dans le mot, pas un deplacement de son centre de gravite. "
     "(3) capacite portee a 128 unites : 44 % -> 47 %. A noter -- la capacite "
     "etait PLATE le 2026-08-04 (29-32 % quoi qu'on fasse) et ne devient utile "
     "QU'APRES l'enrichissement du signal. Le modele etait limite par "
     "l'information, pas par sa taille."),

    ("mort_creux_du_mot_comme_caracteristique_de_tete3",
     "[MORT] Le « creux » du mot (min, p10 du chemin force) n'apporte rien",
     "Hypothese de l'agent, de la meme famille que celle qui avait paye sur "
     "l'etat d'encodeur : une faute ne porte souvent que sur UNE lettre, donc "
     "`forced_v` (moyenne sur le chemin force) serait sourd -- cinq tokens "
     "corrects diluent le sixieme. Ajout de trois caracteristiques : "
     "`forced_min`, `forced_p10`, et `creux = forced_v - forced_min` (12 -> 15). "
     "REFUTE : 47 % avec, 47 % sans -- strictement le meme plafond. Et la "
     "configuration degrade plus vite (34 % a 4500 epochs contre 44 % pour les "
     "12 caracteristiques). Seul effet visible : un meilleur score a FAIBLE "
     "capacite (47 % contre 42 % a 64 unites), c'est-a-dire une information "
     "plus dense, mais qui n'ajoute rien une fois la capacite suffisante -- le "
     "signal etait deja present ailleurs. "
     "A NE PAS REESSAYER sans changer autre chose que la statistique agregee."),

    ("mesure_audio_reel_degrade_une_fois_les_features_corrigees",
     "[MESURE] L'audio reel re-etiquete DEGRADE la tete 3, contrairement a ce qu'on croyait",
     "RENVERSEMENT D'UNE CONCLUSION DE LA VEILLE, et il faut le dire ainsi. Le "
     "2026-08-04, l'audio reel semblait apporter +4 points (33 % TTS seul -> "
     "37 % combine). Mesure refaite le 2026-08-05 avec les caracteristiques "
     "CORRIGEES (cf. mesure_tete3_47_pourcent_et_ses_trois_leviers) : "
     "TTS seul 47 % ; TTS + reel ambigu (8 k clips) 44 % ; TTS + reel COMPLET "
     "(12 k clips, tous types de fautes) 33 %. "
     "Le gain d'hier etait donc un artefact des features buguees -- l'audio "
     "reel compensait un defaut qu'on a depuis supprime. "
     "INTERPRETATION : ces exemples sont trop « propres » (son net contre "
     "etiquette fausse). La tete y apprend un raccourci qui ne transfere pas "
     "aux cas reellement ambigus. "
     "⚠️ RESERVE DE PORTEE : le jeu de test ne contient que des substitutions "
     "de lettres et de harakat (corpus TTS). Ce resultat ne dit donc PAS que "
     "l'audio reel est inutile pour les omissions et insertions -- il dit "
     "qu'il n'aide pas sur les cas ambigus. Trancher demanderait un second jeu "
     "de test couvrant toutes les fautes, qui n'existe pas encore."),

    ("regle_le_plafond_de_tete3_est_en_amont_delle",
     "[REGLE] Le plafond de la tete 3 est dans l'encodeur et le corpus, pas dans la tete",
     "Constat apres six leviers mesures en une nuit (2026-08-05). Tout ce qui "
     "touche a la TAILLE ou au VOLUME degrade : 192 unites 41 %, 8000 epochs "
     "33 %, 30 k clips reels 32 %. Tout ce qui a paye touche a l'INFORMATION, "
     "et cette veine est desormais epuisee -- le dernier ajout (creux du mot) "
     "n'a rien donne. "
     "DEUX LIMITES STRUCTURELLES, toutes deux EN AMONT de la tete : "
     "(1) on lui demande de juger une DEVIATION a partir de l'etat d'un "
     "encodeur entraine a TRANSCRIRE -- rien ne garantit que cette "
     "representation conserve de quoi separer correct et faute ; c'est deja ce "
     "qu'avait montre le 2026-07-31 (une tete sur les logprobs ne bat pas la "
     "formule ecrite a la main : ce n'etait pas la formule, c'est que les "
     "logprobs ont deja jete l'information). "
     "(2) le corpus de fautes est majoritairement SYNTHETIQUE, avec un "
     "rendement d'audibilite de 59 % -- et nul sur certaines paires (ض/ظ a "
     "2 %). "
     "LES DEUX VOIES QUI POURRAIENT DEBLOQUER, lourdes mais reelles : un "
     "encodeur entraine CONTRASTIVEMENT a separer correct/faute (et non a "
     "transcrire), ou un corpus de fautes HUMAINES reelles -- les paires lues "
     "par l'utilisateur le 2026-08-04 en sont le debut. Continuer a regler la "
     "tete est du temps perdu."),
]

LIENS = [
    ("mesure_tete3_47_pourcent_et_ses_trois_leviers",
     "regle_le_plafond_de_tete3_est_en_amont_delle", "aboutit_a",
     "les leviers de la tete sont epuises a 47 %"),
    ("mort_creux_du_mot_comme_caracteristique_de_tete3",
     "regle_le_plafond_de_tete3_est_en_amont_delle", "illustre",
     "ajouter une statistique de plus ne franchit plus le plafond"),
    ("mesure_audio_reel_degrade_une_fois_les_features_corrigees",
     "mesure_tete3_audio_reel_complete_le_tts_sans_le_remplacer", "renverse",
     "le gain de la veille etait un artefact des caracteristiques buguees"),
    ("mesure_audio_reel_degrade_une_fois_les_features_corrigees",
     "piege_confondre_les_instruments_de_mesure", "illustre",
     "une conclusion mesuree avec un instrument fausse s'inverse une fois repare"),
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
            "source_file": "benchmark/NOTE_TETE3_OBJECTIF_80.md",
            "source_location": None, "source_url": None,
            "captured_at": "2026-08-05", "author": None, "contributor": None,
            "rationale": rationale, "_origin": "semantic",
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step25.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
