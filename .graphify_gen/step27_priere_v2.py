#!/usr/bin/env python3
"""Suivre une priere bascule sur la chaine v2 : mesures du 2026-08-07 (commit 1616f36)."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_v1_quasi_muette_en_mode_priere",
     "[MESURE] La v1 ne produit quasi aucun texte en mode priere : 10,10 % de non-verts contre 2,03 % pour la v2",
     "Le suivi de priere tournait sur la v1 (`_onStructured`), la v2 tournant "
     "en parallele sans etre ecoutee. Sur 101 s d'audio (1264 blocs PCM), la "
     "v1 a produit du texte vide presque partout (seuls fragments : "
     "\"يَقْ\", \"ٰ\", \"ٰللَّهُ ٰلْعَـٰلَمِين\"). "
     "`_onStructured` n'a donc jamais eu de texte a examiner. Mesure de "
     "reference du projet, meme flux : v1 10,10 % de mots non verts, v2 "
     "2,03 %. Ce n'est pas un reglage a ajuster."),

    ("regle_mode_priere_bascule_sur_v2",
     "[REGLE] Le mode priere doit tourner sur la chaine v2 (decodage libre + localisation, saut autorise)",
     "Consequence directe de la mesure precedente. Mode `PRIERE` cote "
     "ChaineRecitation (Kotlin, `sautLibre`) : le rejet de fenetre sur trou "
     "trop grand est debraye (le trou reste mesure et remonte, mais n'annule "
     "plus la fenetre), la cible est vide au depart (rien de connu avant "
     "identification), puis alignement force une fois la sourate identifiee. "
     "Specification utilisateur : « le recitant n'attend pas le souffleur, "
     "l'aligneur doit le retrouver ou qu'il soit »."),

    ("piege_quatre_oublis_silencieux_meme_point_dentree",
     "[PIEGE] startPrayerFollow a omis 4 fois la meme chose que startContinuous faisait : moteur, cible v2, capture, decrochage",
     "Meme point d'entree, quatre defauts distincts trouves un par un le "
     "meme jour, chacun SILENCIEUX (aucune ligne de log ne signalait "
     "l'omission) : (1) moteur v2 non declare au demarrage -> heritage de "
     "l'etat du mode precedent (v1Coupee errone) ; (2) cible v2 jamais posee "
     "-> `v2Mots` restait vide, `[V2] mot=` = ZERO sur toute une session ; "
     "(3) capture audio de diagnostic jamais armee -> aucun WAV, donc aucune "
     "verification possible du brut ; (4) flux `decrochage` jamais ecoute -> "
     "`[v2] DECROCHAGE`=2 cote natif, `[CTL][Decrochage]`=0 cote Dart, la "
     "bascule Fatiha->identification ne pouvait jamais s'executer. Lecon : un "
     "second point d'entree qui duplique a la main les abonnements du "
     "premier accumule ce genre de trou -- pas une question de vigilance, "
     "une question de structure."),

    ("mesure_seuil_identification_faux_dun_facteur_quatre",
     "[MESURE] Seuil d'identification de sourate faux d'un facteur ~4 (0,70 vs plafond reel 0,206)",
     "`_kMinIdentifyConfidence` = 0,70 datait d'un ANCIEN scoring (fraction de "
     "recouvrement ordonne), jamais redérive pour le scoring actuel de "
     "QuranVerseLocatorService (vote de decalage sur paires de mots). "
     "Algorithme rejoue hors device sur les requetes REELLES d'une session "
     "(Az-Zukhruf 43:49-51) : le bon verset est PREMIER dans tous les cas, "
     "mais son score plafonne a 0,206, jamais sous 0,088 sur les cas "
     "mesures -- 35 tentatives sur une session reelle, toutes \"0 match(s) "
     "bruts\" avec l'ancien seuil. Un mot fondu ou perdu par l'ASR detruit "
     "TOUTES les paires qui le contiennent, condamnant mecaniquement le "
     "denominateur : exiger 70 % de paires exactes est hors d'atteinte par "
     "construction sur une sortie ASR reelle."),

    ("regle_identification_par_ecart_au_second_et_plancher_de_votes",
     "[REGLE] Decider par l'ECART au second candidat (>= 1,3x) et un plancher de VOTES ABSOLUS (>= 5), pas par un score isole",
     "Remplace le seuil unique 0,70. Mesure sur cas de verite connue : le "
     "bon verset devance toujours le second d'un facteur 1,5 a 2,3x, les "
     "candidats coincidentiels restant groupes au meme niveau (~0,088). "
     "Le ratio SEUL etait un mauvais juge (2 votes/22 paires = 1,50x, "
     "identique a 9 votes/26 -- l'un est du bruit, l'autre une certitude) : "
     "plancher absolu a 5 votes, les cas justes mesures tenant entre 6 et 11, "
     "le seul cas faux mesure a 2. Aucune zone grise mesuree entre les deux."),
]

LIENS = [
    ("regle_mode_priere_bascule_sur_v2", "mesure_v1_quasi_muette_en_mode_priere",
     "s_appuie_sur", "la mesure quantifie pourquoi la v1 ne convient pas"),
    ("piege_quatre_oublis_silencieux_meme_point_dentree", "regle_mode_priere_bascule_sur_v2",
     "complique", "brancher v2 sur un second point d'entree a fait resurgir chaque garde-fou manquant de startContinuous"),
    ("regle_identification_par_ecart_au_second_et_plancher_de_votes", "mesure_seuil_identification_faux_dun_facteur_quatre",
     "corrige", "remplace le seuil unique invalide par un critere mesure"),
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
            "source_file": "app/lib/providers/recitation_provider.dart",
            "source_location": None, "source_url": None,
            "captured_at": "2026-08-07", "author": None, "contributor": None,
            "rationale": rationale, "_origin": "semantic",
            "id": nid, "community": 0, "norm_label": label.lower()})
        a += 1
    connus = {n["id"] for n in g["nodes"]}
    ar = 0
    for s, t, rel, pq in LIENS:
        if s not in connus or t not in connus:
            print(f"  ! cible absente : {s} -> {t}"); continue
        g["links"].append({"source": s, "target": t, "relation_type": rel,
                           "source_location": pq, "rationale": pq})
        ar += 1
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step27.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, {len(g['links'])} aretes")


if __name__ == "__main__":
    main()
