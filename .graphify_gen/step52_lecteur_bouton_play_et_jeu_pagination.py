#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Lecteur Mushaf : bouton play trop petit et chargement invisible. Jeu de
memorisation : le mecanisme d'extension de page verifie sain sur un mode,
absent sur l'autre malgre un commentaire qui l'affirmait."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("regle_bouton_play_zone_tactile_et_chargement_explicite",
     "[REGLE] Un bouton dont l'action peut etre ignoree (chargement en cours) doit le montrer, pas rester identique a l'etat inactif",
     "Retour utilisateur (2026-09-11) : « je n'arrive pas a cliquer [...] "
     "et s'il y a un delai pour charger [...] que ce soit explicite pour "
     "qu'on evite de s'acharner sur l'icone en pensant que le clic ne "
     "marche pas ». Deux causes precises trouvees dans mini_player_bar.dart "
     "avant correction : (1) le bouton play/pause central n'avait qu'un "
     "Padding(all: 4) autour d'une icone de 30 -- zone tactile ~38x38, sous "
     "le minimum usuel (~44) ; (2) pendant PlayerStatus.loading, l'icone "
     "restait play_arrow_rounded -- identique a l'etat pause -- ET "
     "togglePlayPause() ignore silencieusement un tap dans cet etat (ni "
     "isPlaying ni isPaused), donc un clic pendant le chargement ne "
     "produisait RIEN. Corrige : zone portee a 44x44, spinner a la place de "
     "l'icone pendant le chargement, tap desactive (onTap: null) le temps "
     "du chargement plutot que silencieusement ignore. Principe general : "
     "un etat ou l'action de l'utilisateur n'a AUCUN effet doit se "
     "distinguer visuellement des etats ou elle en a un -- sinon "
     "l'utilisateur ne peut pas savoir si son geste a ete recu."),

    ("mesure_jeu_enchainement_pagination_saine_debut_verset_absente",
     "[MESURE] Le jeu \"enchainement\" etend bien sa page automatiquement (verifie sur de vraies pages) ; le mode \"debut de verset\" du meme ecran, non",
     "Signalement utilisateur : « le jeu enchainement ne fait que 6 "
     "versets [...] ca doit continuer a charger les prochains ». Verifie "
     "par execution (test/memorization_game_pagination_test.dart, page 5 du "
     "Coran, 3 transitions de page d'affilee) : memorizationGameProvider "
     "(le jeu enchainement standard, MemorizationGameNotifier._loadNextPage) "
     "etend correctement sa liste de versets via "
     "QuranApi.fetchVersesByPage(page+1) des que le dernier mot charge est "
     "valide -- AUCUN defaut ici, mecanisme sain. Le vrai defaut est dans "
     "le SECOND style du meme ecran (bascule visible a l'ouverture) : "
     "debut_verset_game_provider.dart construit son pool de versets UNE "
     "SEULE FOIS a la creation du notifier, puis boucle dessus indefiniment "
     "(`_index % pool.length`) -- malgre un commentaire du code affirmant "
     "« meme esprit illimite que le jeu d'enchainement ». La classe n'a "
     "meme pas de reference a QuranApi ni au Ref Riverpod pour pouvoir "
     "etendre son pool. Correctif propose (meme principe que "
     "_loadNextPage), en attente de validation utilisateur avant "
     "implementation."),
]

LIENS = [
    ("mesure_jeu_enchainement_pagination_saine_debut_verset_absente",
     "regle_bouton_play_zone_tactile_et_chargement_explicite", "shares_data_with",
     "deux signalements utilisateur consecutifs sur des ecrans differents, meme session"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step52.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print("+{} noeuds, +{} aretes -> {} noeuds, {} aretes".format(
        a, ar, len(g["nodes"]), len(g["links"])))


if __name__ == "__main__":
    main()
