#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Vecteur de reference pour le paquet REELLEMENT DEPLOYE -- sans NeMo.

POURQUOI CE SCRIPT EXISTE, ET EN QUOI IL DIFFERE DE `reference_parite_tete3.py`.

Celui-ci charge un checkpoint NeMo pour produire des logprobs/etat d'encodeur
REELS sur de l'audio reel -- c'est le seul moyen de verifier que les 12
CARACTERISTIQUES (`tete_encodeur_ecart.caracteristiques`) sont extraites de la
meme facon des deux cotes. Cette machine n'a ni torch ni NeMo, ni le
checkpoint `warsh-v5-epoch6.nemo` nomme dans la description de
`cinq-tetes-2026-09-11-madd-normal/tete3.json` -- cette verification-la reste
HORS DE PORTEE ICI et n'est PAS ce que ce script fait.

Ce qu'il verifie est plus etroit mais ne demande QUE les poids : la couche
MLP elle-meme (normalisation -> lineaire -> ReLU -> lineaire) reproduit-elle,
en Python/NumPy, EXACTEMENT ce que fait `Tete3.logit()` en Kotlin -- ordre de
chargement du JSON, orientation des matrices, ordre normalisation/ReLU/biais ?
C'est le risque le plus bete (et deja tombe deux fois sur ce projet selon
`Tete3.kt` : « reimplementer une logique dans deux langages produit des
resultats confiants et faux ») et le seul qu'on peut clore sans encodeur.

Le vecteur d'entree est la MEME formule deterministe que la partie Kotlin
(`Tete3Test.vecteurReference`) : `(((i*37) % 101) - 50) / 25.0`, memes
flottants des deux cotes puisque c'est une formule ENTIERE (pas de sin() ni
d'alea). Recopier ce fichier sans changer cette formule si on l'utilise pour
un test de parite -- sinon les deux cotes comparent des entrees differentes.

USAGE :
    python3 benchmark/reference_parite_tete3_deployee.py \
        app/android/model_pack/src/main/assets/models/cinq-tetes-2026-09-11-madd-normal/tete3.json \
        app/android/model_pack/src/main/assets/models/cinq-tetes-2026-09-11-madd-normal/tete3_warsh.json
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np


def vecteur_reference(n: int) -> np.ndarray:
    return np.array([(((i * 37) % 101) - 50) / 25.0 for i in range(n)],
                     dtype=np.float64)


def logit(tete: dict, x: np.ndarray) -> float:
    """Meme suite d'operations que `Tete3.logit()` en Kotlin, terme a terme :
    normalisation par element, couche 1 (poids1 @ x + biais1), ReLU, somme
    ponderee par poids2, plus biais2. Rien de vectorise en une seule ligne :
    le but est de pouvoir relire ce calcul a cote du Kotlin et voir qu'il
    fait la meme chose, pas d'etre court."""
    mu = np.array(tete["normalisation"]["moyenne"], dtype=np.float64)
    sd = np.array(tete["normalisation"]["ecart_type"], dtype=np.float64)
    if len(mu) != len(x):
        raise SystemExit(
            f"tete attend {len(mu)} caracteristiques, vecteur en a {len(x)}")
    xn = (x - mu) / sd
    c1, c2 = tete["couches"][0], tete["couches"][1]
    poids1 = np.array(c1["poids"], dtype=np.float64)   # (cache, entree)
    biais1 = np.array(c1["biais"], dtype=np.float64)
    poids2 = np.array(c2["poids"][0], dtype=np.float64)  # une seule sortie
    biais2 = float(c2["biais"][0])
    s = 0.0
    for j in range(poids1.shape[0]):
        a = biais1[j] + float(poids1[j] @ xn)
        if a > 0.0:
            s += poids2[j] * a
    return s + biais2


def main():
    p = argparse.ArgumentParser()
    p.add_argument("fichiers", nargs="+", help="un ou plusieurs tete3*.json")
    p.add_argument("--sortie", default=None,
                   help="JSON de sortie (defaut : a cote de chaque fichier, "
                        "suffixe _reference_arithmetique.json)")
    a = p.parse_args()

    resultats = []
    for chemin in a.fichiers:
        f = Path(chemin)
        brut = f.read_bytes()
        tete = json.loads(brut.decode("utf-8"))
        n = len(tete["normalisation"]["moyenne"])
        x = vecteur_reference(n)
        lg = logit(tete, x)
        r = {
            "fichier": str(f),
            "sha256": hashlib.sha256(brut).hexdigest(),
            "description": tete.get("description"),
            "seuils_mesures": tete.get("seuils_mesures"),
            "taille_entree": n,
            "cache": len(tete["couches"][0]["poids"]),
            "logit_reference": round(lg, 6),
        }
        resultats.append(r)
        sortie = Path(a.sortie) if a.sortie else f.with_name(
            f.stem + "_reference_arithmetique.json")
        sortie.write_text(json.dumps({
            "commentaire": (
                "Reference PUREMENT ARITHMETIQUE (pas d'encodeur, cf. l'en-tete "
                "de reference_parite_tete3_deployee.py) pour le fichier "
                f"{f.name}. Verifie le chargement JSON et le forward MLP, PAS "
                "l'extraction des 12 caracteristiques depuis l'audio."
            ),
            **r,
        }, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"{f}")
        print(f"  sha256           {r['sha256']}")
        print(f"  taille_entree    {n}  (cache={r['cache']})")
        print(f"  seuils_mesures   {r['seuils_mesures']}")
        print(f"  logit_reference  {lg:.6f}")
        print(f"  -> {sortie}")
        print()

    return resultats


if __name__ == "__main__":
    main()
