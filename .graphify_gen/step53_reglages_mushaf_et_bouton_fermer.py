#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Reglages recitateur/ecriture/riwaya deplaces cote Mushaf ; le lecteur
n'avait aucun chemin vers stop()."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("regle_reglages_pres_du_geste_pas_dans_un_tiroir_general",
     "[REGLE] Un reglage change en train de lire doit vivre pres du geste de lecture, pas au fond des Reglages generaux",
     "Demande utilisateur (2026-09-11) : « je trouve que mettre "
     "recitateur ecriture et lecture dans parametre generale [c'est pas] "
     "le mieux, les mettre [...] plus cote mushaf facile d'acces ». "
     "Recitateur, ecriture du Mushaf et riwaya deplaces de "
     "settings_screen.dart vers le tiroir « Plus » du Mushaf "
     "(reading_settings_sheet.dart), deja groupe par intention "
     "LIRE/ECOUTER (regle du 2026-08-05). Ecriture et riwaya rejoignent "
     "LIRE (juste apres la taille du texte -- meme famille : comment le "
     "texte s'ecrit) ; recitateur rejoint ECOUTER, en tete, avant la "
     "vitesse. Les commentaires historiques de settings_screen.dart "
     "expliquant pourquoi ces reglages y avaient ete places (recitateur "
     "transverse, 2026-07-20 ; riwaya, 2026-08-12 ; ecriture, 2026-09-03) "
     "sont conserves tels quels avec une note de migration -- ils restent "
     "vrais comme historique, meme si le code qu'ils documentaient est "
     "parti. Principe general : la bonne place d'un reglage n'est pas "
     "fixe, elle depend du geste qui le declenche le plus souvent -- ici "
     "un geste DE LECTURE, pas un geste de configuration ponctuelle."),

    ("mesure_lecteur_aucun_chemin_vers_stop",
     "[MESURE] MiniPlayerBar : aucun bouton n'appelait stop(), le bouton central ne fait que pause/reprise",
     "Retour utilisateur : « pour arreter la lecture j'ai besoin de "
     "taper deux fois sur le widget, une pour arreter la lecture et "
     "l'autre pour disparaitre le widget ». Verifie par grep exhaustif "
     "des appelants de playerProvider.notifier.stop() dans lib/ : "
     "coach_screen.dart, dua_collection_screen.dart, dua_card.dart -- "
     "AUCUN dans mini_player_bar.dart ni mushaf_screen.dart. Le bouton "
     "central de la barre ne fait que togglePlayPause() (pause()/"
     "resume(), jamais idle) ; la barre ne disparait que quand "
     "status==idle (cf. la condition en tete de MiniPlayerBar.build()). "
     "Un des deux taps que l'utilisateur decrivait relancait donc la "
     "lecture (resume) au lieu de fermer quoi que ce soit -- pas un "
     "double-tap redondant, un geste qui faisait l'inverse de ce qui "
     "etait attendu. Corrige par un bouton ferme (icone X) explicite "
     "appelant stop() directement."),
]

LIENS = [
    ("mesure_lecteur_aucun_chemin_vers_stop",
     "regle_reglages_pres_du_geste_pas_dans_un_tiroir_general", "shares_data_with",
     "deux signalements utilisateur consecutifs sur le meme lecteur Mushaf, meme session"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step53.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print("+{} noeuds, +{} aretes -> {} noeuds, {} aretes".format(
        a, ar, len(g["nodes"]), len(g["links"])))


if __name__ == "__main__":
    main()
