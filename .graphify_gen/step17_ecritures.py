#!/usr/bin/env python3
"""Consigne l'ALIGNEMENT SUR TOUTES LES ECRITURES (2026-08-06) : refute,
et deux regles d'IHM/jugement.

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
    ("mort_alignement_sur_toutes_les_ecritures_de_la_bande",
     "[MORT] Ouvrir TOUTES les ecritures du mot pour toute la bande",
     "IDEE : l'aligneur cesse d'aligner une tokenisation figee et aligne LE MOT, "
     "en autorisant toute segmentation valide de ses lettres en pieces du "
     "vocabulaire (graphe de 12 noeuds / 19 aretes en mediane, 68 chemins "
     "implicites, jusqu'a 1800). Implemente et mesure le 2026-08-06. "
     "SUR LE CAS ISOLE, C'EST PARFAIT (banc PlancherDureeTest) : le mot dont la "
     "cible imposait une piece que le modele n'avait pas produite passe de "
     "frames=1 / gop=-11,99 / entendu=\"r\" a frames=14 / gop=0,00 / entendu "
     "complet. "
     "MESURE QUI LE TUE, rejeu DETERMINISTE du meme WAV Al-Baqara, meme binaire "
     "a ce parametre pres : 2/295 = 0,68 % de non verts SANS, 22/295 = 7,46 % "
     "AVEC. ONZE FOIS PLUS. "
     "CE QUE CA APPREND : la tokenisation du dictionnaire ne genait pas, elle "
     "CONTRAIGNAIT utilement. Libre de re-epeler chaque mot, la DP trouve des "
     "chemins qui marquent bien localement mais deplacent les frontieres de "
     "mots, et les voisins paient. Le code (`AligneurForce.grapheEcritures` + "
     "parametre `textesParMot`) est CONSERVE et non branche. "
     "PISTE BORNEE, non mesuree : n'ouvrir les ecritures que pour le SEUL mot "
     "qui presente la signature (free proche de 0, gop effondre, tres peu de "
     "frames), APRES l'alignement, en rescorant sur l'audio laisse libre entre "
     "ses deux voisins -- l'alignement global restant intact. Le mecanisme "
     "existe deja (`variantesParMot`), il lui manque la plage elargie."),

    ("regle_le_blocage_suit_le_reglage_pas_une_heuristique",
     "[REGLE] Le blocage suit le REGLAGE de l'utilisateur, pas une heuristique",
     "SPECIFICATION UTILISATEUR (2026-08-06) : « j'ai active la correction "
     "automatique, donc il aurait du me bloquer a CHAQUE erreur ; quand c'est "
     "desactive il n'y a pas de blocage sauf en cas de decrochage, qui reste "
     "tout le temps actif ». "
     "DEUX ECARTS CORRIGES : (1) la regle « deux mots consecutifs » (posee le "
     "2026-08-01 sur la mesure du 2026-07-28 : 8 mots non verts, 0 vraie "
     "erreur) decidait a la place de l'utilisateur -- cocher « correction "
     "automatique » veut dire « reprends-moi », pas « une fois sur deux ». "
     "Retiree. (2) le garde-fou `if (!autoCorrectionEnabled) return` barrait "
     "AUSSI `surSilence`, donc le DECROCHAGE ne partait jamais des qu'on "
     "decochait la correction -- alors que c'est le cas ou l'aide est "
     "indispensable. Il ne barre plus que les erreurs. "
     "⚠️ SI LES INTERRUPTIONS SUR FAUX POSITIFS REVIENNENT, la reponse n'est PAS "
     "de remettre la regle des deux mots : c'est de reduire les faux positifs."),

    ("piege_reessai_valide_a_75_pourcent",
     "[PIEGE] La boucle de correction validait un mot « a 75 % »",
     "DEFAUT SIGNALE (2026-08-06) : « dans reessayer le mot, la il m'affiche "
     "autre chose et il dit c'est ok ». Le critere etait "
     "`ArabicNormalizer.similarity(entendu, attendu) >= 0.75` sur le squelette : "
     "un mot avec une lettre fausse le franchissait. L'ecran affichait alors le "
     "mot REELLEMENT entendu -- donc un autre mot -- et annoncait « Corrige ». "
     "Deux fautes en une : valider ce qui ne l'est pas, et le montrer a "
     "l'utilisateur en le felicitant. Meme famille que le palliatif refuse le "
     "2026-07-25 (« un recitateur qui ne dit que la moitie d'un mot etait alors "
     "valide »). Corrige : le squelette doit etre EGAL."),
]

LIENS = [
    ("mort_alignement_sur_toutes_les_ecritures_de_la_bande",
     "piege_cible_impose_une_piece_que_le_modele_n_emet_pas", "tentative_sur"),
    ("mort_alignement_sur_toutes_les_ecritures_de_la_bande",
     "mort_plancher_de_duree_fonde_sur_les_lettres", "meme_zone"),
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
        shutil.copy2(GRAPHE, SORTIE / "graph_avant_ecritures.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")
    print("sauvegarde de l'etat precedent : graphify-out/graph_avant_ecritures.json")


if __name__ == "__main__":
    main()
