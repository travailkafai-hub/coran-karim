#!/usr/bin/env python3
"""Consigne le franchissement de FRONTIERE DE SOURATE (2026-08-06).

Meme principe que step10_decrochage.py : on enrichit, on n'ecrase pas, et
le `rationale` porte LE CHIFFRE ou LA LIGNE DE LOG -- jamais l'intention.

Contexte : une soiree entiere de correctifs sur le decrochage / SAUT REFUSE,
dont la moitie visaient le mauvais maillon. Ce fichier existe pour qu'on ne
repaye pas ces heures -- chaque noeud dit ce qui a ETE MESURE, pas ce qui a ete
espere.

Protocole des mesures : sessions reelles sur device (Samsung R3CY20XW7TD),
builds v49 a v57, sourates 90/93/95, mode NORMALE sauf mention, journal
`recitation_diagnostic.log` + flux brut `stream_*.wav` confronte au modele.
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("piege_bismillah_comptee_comme_saut_de_4_mots",
     "[PIEGE] La Bismillah d'une nouvelle sourate comptait comme un saut de "
     "4 mots",
     "MESURE (2026-08-06, session live, build v79 -- « j'ai recite puis pause "
     "puis play pour passer a une autre sourate, rien ne se passe »). "
     "Al-Kafirun terminee, ancre au mot 29 ; la cible insere la Bismillah de "
     "la sourate suivante aux mots 30-33. Le recitateur enchaine sur "
     "Al-Ikhlas et la chaine le VOIT parfaitement : `f=30 SAUT REFUSE : trou "
     "de 4 mots apres le mot 29 (attestes=[34, 35, 36, 37, 38])` -- 34-38 = "
     "`قُلْ هُوَ ٱللَّهُ أَحَدٌ ٱللَّهُ`, confirme au balayage du flux brut. "
     "L'ecart 29->34 vaut 4 mots, au-dessus de sautMaxMots=2 : fenetre jetee "
     "VINGT fois de suite jusqu'a la fin. La Bismillah avait pourtant ete dite "
     "(`entendu=\"بِسْمِ\"` trois fois) mais n'a pas pu etre placee : un mot "
     "SEUL qui se repete dans la zone de recherche est refuse par securite, et "
     "`بسم` y figure trois fois (sourates 112, 113, 114). "
     "PORTEE : aucun recitateur ne pouvait franchir une frontiere de sourate "
     "-- la fonction « enchainer sur une autre sourate » etait cassee en "
     "entier, et le defaut est reste invisible parce que toutes les mesures "
     "portaient sur UNE sourate. "
     "CORRECTIF : le compteur de saut ne compte QUE les mots jugeables. Un mot "
     "que l'app refuse de juger par conception (Bismillah, decision "
     "2026-07-20) ne peut pas servir de preuve qu'on a saute. Les index "
     "viennent de Dart (`RecitedWord.isBasmala`), seule autorite : les "
     "detecter sur le texte cote Kotlin confondrait la Bismillah INSEREE avec "
     "le verset 1:1 d'Al-Fatiha, qui lui est bien recite. "
     "RESULTAT (rejeu deterministe du WAV de l'utilisateur, sourate 109 puis "
     "112) : ancre 29 -> 40, SAUT REFUSE 20 -> 1."),

    ("piege_fil_de_lumiere_colle_a_l_index_zero",
     "[PIEGE] Le repere visuel suivait un marqueur que la v2 ne pose jamais",
     "MESURE (2026-08-06, retour utilisateur : « le fil de lumiere n'est pas "
     "visible »). Le fil suivait `WordStatus.current`, avec repli sur "
     "`state.pointer`. Or `_onV2` met a jour les STATUTS des mots et rien "
     "d'autre : `pointer` reste a 0 (piege deja documente pour le souffleur) "
     "et `current` n'est pose qu'a l'index 0 au reset. Le fil est donc reste "
     "colle aux six premiers mots -- dans la Bismillah -- pendant toute la "
     "recitation. CORRECTIF : le front est le plus grand index deja JUGE, la "
     "v2 ne rendant un statut que sur un mot qu'elle a vu. REGLE GENERALE : "
     "tout element d'IHM qui suit « ou en est le recitateur » doit se deduire "
     "des STATUTS, jamais d'un pointeur que la v2 n'alimente pas."),
]

LIENS = [
    ("piege_bismillah_comptee_comme_saut_de_4_mots",
     "regle_a_egalite_avancer_plutot_que_reculer", "meme_zone"),
]

CORRECTIONS = {}


def noeud(nid, label, rationale):
    return {"id": nid, "label": label, "rationale": rationale,
            "node_type": "concept", "community": "recitation"}


def sha() -> str:
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=RACINE,
                          capture_output=True, text=True).stdout.strip()


def main():
    g = json.loads(GRAPHE.read_text(encoding="utf-8"))
    connus = {n["id"] for n in g["nodes"]}
    ajoutes = 0
    for nid, label, rationale in NOEUDS:
        if nid not in connus:
            g["nodes"].append(noeud(nid, label, rationale))
            ajoutes += 1
        else:
            # On ENRICHIT sans ecraser : si le noeud existe deja, on ne touche
            # a rien (regle projet -- aucune piste n'est jamais ecrasee).
            print(f"  = deja present, inchange : {nid}")

    corriges = 0
    for n in g["nodes"]:
        if n["id"] in CORRECTIONS:
            n["rationale"] = CORRECTIONS[n["id"]]
            corriges += 1
            print(f"  ~ rationale CORRIGE (mesure invalide) : {n['id']}")
    print(f"  {corriges} noeud(s) corrige(s)")

    connus = {n["id"] for n in g["nodes"]}
    aretes = 0
    for s, t, rel in LIENS:
        if s not in connus or t not in connus:
            print(f"  ! cible absente, arete ignoree : {s} -> {t}")
            continue
        g["links"].append({
            "source": s, "target": t, "relation_type": rel,
            "source_location": None, "rationale": None,
        })
        aretes += 1

    if GRAPHE.exists():
        shutil.copy2(GRAPHE, SORTIE / "graph_avant_bismillah.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")
    print("sauvegarde de l'etat precedent : graphify-out/graph_avant_bismillah.json")


if __name__ == "__main__":
    main()
