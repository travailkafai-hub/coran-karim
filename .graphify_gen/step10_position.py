#!/usr/bin/env python3
"""Consigne les deux changements « fondes mais sans gain immediat » du 2026-07-30.

POURQUOI CES NOEUDS EXISTENT alors qu'ils ne portent aucun gain chiffre.

Remarque de l'utilisateur, le jour meme : « une amelioration non mesuree + une
autre, ca peut marcher ». La regle projet « un changement sans effet mesurable
n'a pas sa place dans la chaine critique » vient du retrait de
FRONTIER_KEEP_SECONDS (2026-07-29) -- mais LA, l'hypothese avait ete REFUTEE par
l'intervention en plus d'etre sans effet. Ce n'est pas la meme situation.

Le graphe doit donc distinguer trois etats, et pas deux :
  [MORT]        mesure perdant, ou hypothese refutee
  [EN ATTENTE]  fonde, garde, mais SANS GAIN MESURE AUJOURD'HUI
  [MESURE]      gain chiffre

Sans ce troisieme etat, un futur agent lit « pas de gain » et supprime un
mecanisme correct.
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("attente_position_chevauchement",
     "[EN ATTENTE] Le forced ne condamne pas un mot pose sur l'audio d'un AUTRE mot",
     "FONDE, GARDE, SANS GAIN MESURE AUJOURD'HUI (10/295 = 3,39 % avant comme "
     "apres). Defaut nomme par l'utilisateur : « le GOP forced condamne alors "
     "que le free est confiant ». Signature relevee : mot 172 gop=-11,14 "
     "free=-0,01 entendu vide ; mot 228 gop=-8,79 free=-0,05 ; mot 172 en f37 "
     "gop=-14,18 entendu=\"ٱلْبَرْء\", c'est-a-dire l'audio du mot 170. Un free "
     "proche de 0 veut dire que le modele SAIT ce qu'il entend : si c'est un "
     "autre mot attendu, le mot juge n'est pas la. `sansCreneau` teste "
     "desormais le chevauchement avec la plage de N'IMPORTE QUEL autre mot "
     "atteste, et plus seulement les bornes des voisins les plus proches -- "
     "quand ceux-la manquaient dans le bloc, il ne voyait rien. "
     "A re-mesurer des qu'un autre defaut de position sera traite."),
    ("attente_attestation_au_bord",
     "[EN ATTENTE] L'attestation du decodage libre vaut aussi AU BORD d'un bloc",
     "FONDE, GARDE, SANS GAIN MESURE AUJOURD'HUI (10/295 avant comme apres). "
     "Un mot au bord est suspect parce qu'il pourrait etre TRONQUE ; mais si le "
     "decodage libre l'a emis ENTIER, il ne l'est pas -- l'attestation repond "
     "deja a la question que la marge posait. Mesure qui motive : le mot 67 "
     "etait lu gop=0,00 avec son texte EXACT et ressortait quand meme `Omis`, "
     "faute d'observation interieure."),
    ("piege_falaise_pause_min",
     "[PIEGE] Le seuil de pause a une FALAISE entre 0,30 s et 0,35 s",
     "MESURE (flux brut de reference, tout le reste identique) : pause 0,25 s "
     "-> 3,39 % de mots non verts | 0,30 s -> 3,39 % | 0,35 s -> 65,76 %. Une "
     "falaise entre deux valeurs voisines n'est pas un reglage, c'est un defaut "
     "de conception : la chaine depend d'un parametre qui n'a aucune plage "
     "stable. A traiter AVANT de brancher la v2 a l'ecran -- un recitateur qui "
     "respire autrement ferait basculer l'app d'un cote ou de l'autre de la "
     "falaise sans que personne comprenne pourquoi.",),
]

LIENS = [
    ("attente_position_chevauchement", "piege_gop_vs_free", "traite",
     "la formulation exacte du piege, testee sur les plages de frames"),
    ("attente_position_chevauchement", "couche_v2_e_alignement", "nait_dans", None),
    ("attente_attestation_au_bord", "couche_v2_g_decision", "s_applique_a", None),
    ("piege_falaise_pause_min", "couche_v2_b_fenetres", "nait_dans", None),
    ("piege_falaise_pause_min", "mesure_decoupage_silences", "limite",
     "le gain du decoupage aux silences ne tient que dans une plage etroite"),
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
    for entree in NOEUDS:
        nid, label, rationale = entree[0], entree[1], entree[2]
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

    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step10.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
