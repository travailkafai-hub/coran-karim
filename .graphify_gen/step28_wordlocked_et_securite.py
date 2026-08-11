#!/usr/bin/env python3
"""Rattrape le retard du graphe sur les commits 9036be4 et f8a8892 (2026-08-11).

Les deux commits touchent des fichiers de la chaine (recitation_provider.dart,
recitation_verifier.dart, fastconformer_verifier.dart) mais AUCUN des deux
n'altere le jugement (seuils GOP, alignement force, decodage) -- rien a
mesurer en WER ici. Consigne pour que le graphe reste une source fiable de
"qu'est-ce qui a ete mesure", pas seulement "qu'est-ce qui a change dans ces
fichiers" : ces noeuds disent explicitement l'absence de mesure, plutot que de
la laisser dans un flou que le prochain agent pourrait lire comme "peut-etre
teste, jamais consigne".
"""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("regle_wordlocked_flux_observation_pure_sans_impact_jugement",
     "[REGLE] `wordLocked` (recitation_provider.dart) est un flux D'OBSERVATION, aucun impact sur le jugement",
     "Ajoute pour le suivi permanent par portion du Coach (commit 9036be4) : "
     "signale TOUT mot verrouille (vert compris), a cote de `wordLockedNonGreen` "
     "qui existait deja. Alimente uniquement l'archivage (portion_words) --  "
     "aucun seuil GOP, aucune regle d'alignement, aucun chemin de decision "
     "touche. Rien a mesurer en WER : le verdict pose par `_judge` est "
     "strictement le meme avant/apres, seul un evenement supplementaire est "
     "emis apres coup."),

    ("regle_verrou_modele_externe_et_capture_en_cours_sans_impact_jugement",
     "[REGLE] Verrou du modele ASR externe (release) et `captureEnCours` (GardeMicro) : securite/observation, pas de jugement touche",
     "Commit f8a8892. Deux ajouts distincts dans recitation_verifier.dart / "
     "fastconformer_verifier.dart : (1) `captureEnCours` est un getter pur "
     "(`_pcmSub != null`), lu par GardeMicro pour savoir s'il faut relacher le "
     "micro -- ne participe a aucun verdict. (2) le chargement du modele "
     "FastConformer depuis le stockage externe est desormais conditionne a "
     "`kDebugMode` : ferme une porte de substitution de modele en build "
     "release (n'importe quelle app pouvait deposer un ONNX fabrique dans le "
     "dossier externe et le faire preferer a celui embarque). Aucun seuil, "
     "aucune logique de decodage ou d'alignement modifie -- le modele CHARGE "
     "reste le meme fichier, seule la SOURCE autorisee en release change."),
]

LIENS = []


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
            "captured_at": "2026-08-11", "author": None, "contributor": None,
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step28.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, {len(g['links'])} aretes")


if __name__ == "__main__":
    main()
