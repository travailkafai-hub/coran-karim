#!/usr/bin/env python3
"""Consigne le MICRO RETENU hors recitation (2026-08-06).

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
    ("piege_micro_retenu_apres_sortie_d_ecran",
     "[PIEGE] Le micro reste detenu apres la sortie de l'ecran de recitation",
     "CONSTAT UTILISATEUR (2026-08-06), en lisant le Mushaf : « je vois le "
     "micro allume, il n'y a pas de raison, je ne suis pas en recitation ». "
     "VERIFIE SUR L'APPAREIL : `appops get com.corankarim.coran_karim "
     "RECORD_AUDIO` -> `allow; time=+8m35s ago (RUNNING)` -- l'application "
     "detenait le micro depuis huit minutes, depuis qu'elle avait quitte la "
     "recitation. "
     "CAUSE : seul `_recorder.stop()` relache le micro, et il n'est appele que "
     "par `RecitationVerifier.stop()`. `pauseCapture()` fait "
     "`_recorder.pause()` : l'objet AudioRecord reste VIVANT et Android "
     "maintient son indicateur de confidentialite tant qu'il l'est. Et le "
     "`dispose()` de l'ecran karaoke n'appelait ni l'un ni l'autre. "
     "MEME RACINE que le defaut deja documente le meme jour (`capture "
     "ouverte`=3, trace de fermeture=0, d'ou les derniers mots jamais juges), "
     "mais avec une consequence bien plus grave : garder le micro d'un "
     "utilisateur qui ne recite plus. "
     "REGLE : pause n'est pas liberation. Tout chemin de SORTIE doit relacher "
     "la ressource, pas la suspendre."),

    ("piege_fonction_nommee_close_qui_ne_ferme_rien",
     "[PIEGE] Une fonction nommee `_closeAudioCapture` qui ne ferme pas l'audio",
     "`_closeAudioCapture()` ne fait que `setClipCapture(null)` : elle coupe "
     "l'ECRITURE DU WAV de diagnostic, pas la capture micro. Son nom a "
     "entretenu la croyance que le chemin d'arret relachait le micro -- un "
     "commentaire de `_toggle` dit meme « fermer la capture audio a CHAQUE "
     "arret ». Le defaut du micro retenu a vecu derriere ce nom. REGLE : quand "
     "un mecanisme semble present mais sans effet, lire ce que la fonction "
     "FAIT, pas ce qu'elle s'appelle."),
]

LIENS = [
    ("piege_micro_retenu_apres_sortie_d_ecran",
     "piege_fonction_nommee_close_qui_ne_ferme_rien", "masque_par"),
    ("piege_micro_retenu_apres_sortie_d_ecran",
     "piege_session_jamais_fermee_fin_de_recitation", "meme_racine"),
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
        shutil.copy2(GRAPHE, SORTIE / "graph_avant_micro.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")
    print("sauvegarde de l'etat precedent : graphify-out/graph_avant_micro.json")


if __name__ == "__main__":
    main()
