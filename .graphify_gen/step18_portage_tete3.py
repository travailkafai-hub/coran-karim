#!/usr/bin/env python3
"""Portage Kotlin de la tete 3 : les deux briques posees, les deux qui restent."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_etat_encodeur_lu_cote_kotlin",
     "[MESURE] L'etat de l'encodeur est lu cote Kotlin, sans regression",
     "Deux briques posees et compilees sur la branche `tete3-ecart-canonique`. "
     "(1) `CtcOutputs.etatEncodeur` -- recuperation PAR NOM de la sortie "
     "`encoder_state`, comme la tete tajwid, donc robuste a un reordonnancement "
     "de l'exporteur et ABSENTE SANS ERREUR sur les modeles a une seule sortie. "
     "(2) `FrontAcoustique.sorties()` rend logprobs ET etat en UN SEUL appel au "
     "modele : deux methodes separees auraient fait tourner l'encodeur DEUX FOIS "
     "par fenetre, d'autant plus inacceptable que le curseur glissant en emet "
     "une toutes les 3 s. L'etat est null quand le modele ne l'expose pas -- "
     "l'ancien export et les bancs JVM continuent de fonctionner sans "
     "modification. "
     "MESURE SUR DEVICE du modele a deux sorties, avant tout branchement de la "
     "tete : 2,17 % de mots non verts, attente 3,1 s -- dans l'intervalle des "
     "deux passes de reference (2,03 % et 2,71 %). La prise ne coute rien."),
    ("attente_appliquer_tete3_par_mot",
     "[EN ATTENTE] Charger tete3.json et l'appliquer par mot",
     "DERNIERS MAILLONS, entierement specifies, sans recherche ni arbitrage : "
     "charger `tete3.json` (normalisation, deux couches lineaires, seuils "
     "mesures) au demarrage a cote du modele ; puis, par mot, moyenner l'etat de "
     "l'encodeur sur les frames du mot (512), concatener les 12 scores "
     "conditionnes par la cible deja calcules, appliquer les deux couches, et "
     "remonter le logit au Decideur. "
     "16 833 parametres, 380 Ko. Detection mesuree hors device : 31 % contre "
     "27 % pour la regle ecrite a la main, a 2 % de collateral. "
     "JUGEABLE : le banc mesure de nouveau depuis le passage a la cadence "
     "absolue (165/167 fenetres au lieu de 159/170, incertitude ~0,7 point), "
     "donc +4 points seront visibles -- ce qui n'aurait pas ete le cas le matin "
     "meme."),
    ("regle_retour_arriere_a_trois_niveaux",
     "[REGLE] Le retour arriere doit exister a CHAQUE niveau touche",
     "Condition posee par l'utilisateur avant de donner son autonomie : « je te "
     "laisse gerer tant que tu m'assures qu'on peut revenir a la version de "
     "reference ». Trois niveaux, parce que ce chantier en touche trois : "
     "(1) le CODE -- branche `tete3-ecart-canonique` isolee, `recitation-v2` "
     "intacte avec les tags v2-blocs-2.61pct, v2-curseur-3.1s, "
     "v2-frontiere-2.37pct ; (2) le MODELE sur le telephone -- l'ancien "
     "model.onnx sauvegarde en `model.onnx.avant_tete3` AVANT le push ; (3) le "
     "GRAPHE -- chaque step sauvegarde l'etat precedent (graph_avant_stepNN). "
     "Un retour arriere qui ne couvre que le code laisserait le telephone sur un "
     "modele que plus aucun commit ne decrit."),
]

LIENS = [
    ("mesure_etat_encodeur_lu_cote_kotlin", "attente_portage_kotlin_tete3", "avance", None),
    ("attente_appliquer_tete3_par_mot", "attente_portage_kotlin_tete3", "reste_de", None),
    ("attente_appliquer_tete3_par_mot", "regle_preferer_une_tete_a_une_regle_ecrite",
     "realise", None),
    ("regle_retour_arriere_a_trois_niveaux", "attente_portage_kotlin_tete3", "encadre", None),
]


def sha(ref="HEAD"):
    try:
        return subprocess.run(["git","rev-parse",ref],capture_output=True,text=True,
                              cwd=RACINE,timeout=5).stdout.strip()
    except Exception:
        return ""


def main():
    g = json.loads(GRAPHE.read_text(encoding="utf-8"))
    connus = {n["id"] for n in g["nodes"]}
    a = 0
    for nid, label, rat in NOEUDS:
        if nid in connus: continue
        g["nodes"].append({"label": label, "file_type": "concept",
            "source_file": "SOLUTIONS_RECITATION_V2.md", "source_location": None,
            "source_url": None, "captured_at": "2026-07-31", "author": None,
            "contributor": None, "rationale": rat, "_origin": "semantic",
            "id": nid, "community": 0, "norm_label": label.lower()})
        a += 1
    connus = {n["id"] for n in g["nodes"]}
    e = 0
    for s, t, rel, pq in LIENS:
        if s not in connus or t not in connus:
            print(f"  ! cible absente : {s} -> {t}"); continue
        g["links"].append({"source": s, "target": t, "relation_type": rel,
                           "source_location": pq, "rationale": pq}); e += 1
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step18.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{e} aretes -> {len(g['nodes'])} noeuds, {len(g['links'])} aretes")


if __name__ == "__main__":
    main()
