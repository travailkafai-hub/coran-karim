#!/usr/bin/env python3
"""Balayage systematique des variantes de la tete 3, sur le MEME jeu de test.

OBJECTIF FIXE PAR L'UTILISATEUR (2026-08-05) : 80 % de detection a 2 % de
collateral. Point de depart mesure : 37 % (TTS + audio reel re-etiquete),
contre 28 % pour la regle ecrite a la main.

POURQUOI UN BALAYAGE ET PAS DES ESSAIS AU FIL DE L'EAU. Le projet a deja paye
d'annoncer un gain qui n'existait pas (`minAppariements`, 2026-08-04) faute de
comparer a la bonne reference. Ici toutes les variantes partagent LE MEME jeu
de test -- les 189 premieres phrases TTS, tenues a l'ecart depuis l'origine --
et la meme graine. Un ecart lu dans ce tableau est donc attribuable.

CE QUI EST BALAYE :
  - jeu de caracteristiques : 12 scores seuls, etat seul, etat+scores, et les
    variantes d'etat (moyenne seule contre moyenne+ecart-type) ;
  - capacite de la tete et duree d'entrainement ;
  - dosage TTS / audio reel, qui s'est deja revele NON monotone (37 % a 8 000
    clips reels, 32 % a 30 000 : plus de donnees peut nuire).

LE JUGE est `detection a 2 % de collateral`, pas l'AUC : c'est le point de
fonctionnement ou l'app doit vivre -- accuser 2 % des mots corrects est deja
beaucoup pour un recitateur.
"""
import argparse
import itertools
import json
from pathlib import Path

import numpy as np
import torch

BASE = Path(__file__).parent
import sys
sys.path.insert(0, str(BASE))
from tete_ecart_canonique import detection_a_collateral, entrainer  # noqa: E402


def charger(chemins):
    """Concatene plusieurs caches. Le TEST vient TOUJOURS du premier (le TTS,
    seul jeu comparable a l'historique du projet) ; tout le reste part en
    entrainement, jamais en test."""
    E, X, y, test = [], [], [], []
    for k, c in enumerate(chemins):
        z = np.load(c)
        E.append(z["E"]); X.append(z["X"]); y.append(z["y"])
        test.append(z["test"] if k == 0 else np.zeros(len(z["y"]), dtype=bool))
    return (np.concatenate(E), np.concatenate(X),
            np.concatenate(y), np.concatenate(test))


def auc(sf, sc):
    a = np.concatenate([sf, sc])
    r = a.argsort().argsort() + 1
    return (r[:len(sf)].sum() - len(sf) * (len(sf) + 1) / 2) / (len(sf) * len(sc))


def evaluer(A, y, test, cache, epochs, graine=0):
    ap, at = ~test, test
    mu, sd = A[ap].mean(0), A[ap].std(0) + 1e-6
    An = (A - mu) / sd
    poids = float((y[ap] == 0).sum() / max(1, (y[ap] == 1).sum()))
    torch.manual_seed(graine)
    m, npar, _ = entrainer(An[ap], y[ap], poids, epochs=epochs, cache=cache)
    with torch.no_grad():
        s = m(torch.tensor(An[at], dtype=torch.float32)).squeeze(1).numpy()
    sf, sc = s[y[at] == 1], s[y[at] == 0]
    d2 = detection_a_collateral(sf, sc, 0.02)[0]
    d5 = detection_a_collateral(sf, sc, 0.05)[0]
    d10 = detection_a_collateral(sf, sc, 0.10)[0]
    return auc(sf, sc), d2, d5, d10, npar


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--caches", nargs="+", required=True,
                   help="le PREMIER fournit le jeu de test")
    p.add_argument("--sortie", default=None, help="journal JSON des resultats")
    a = p.parse_args()

    E, X, y, test = charger(a.caches)
    ok = np.isfinite(X).all(1) & (np.abs(X) < 1e6).all(1) & np.isfinite(E).all(1)
    rejetes = int((~ok).sum())
    E, X, y, test = E[ok], X[ok], y[ok], test[ok]
    dim = E.shape[1]
    demi = dim // 2
    print(f"{len(y)} exemples ({int(y.sum())} fautes), etat {dim}D, "
          f"{rejetes} rejetes par le filtre")
    print(f"entrainement {int((~test).sum())} | test {int(test.sum())} "
          f"({int(y[test].sum())} fautes)\n")

    # L'etat peut etre [moyenne] (512) ou [moyenne|ecart-type] (1024).
    jeux = {"scores seuls": X, "etat seul": E, "etat + scores": np.hstack([E, X])}
    if dim == 1024:
        jeux["moyenne seule + scores"] = np.hstack([E[:, :demi], X])
        jeux["ecart-type seul + scores"] = np.hstack([E[:, demi:], X])

    resultats = []
    print(f"{'jeu':>26} {'cache':>6} {'epochs':>7} {'AUC':>7} "
          f"{'det@2%':>7} {'det@5%':>7} {'det@10%':>8} {'par.':>8}")
    print("-" * 92)
    for nom, A in jeux.items():
        for cache, epochs in itertools.product((32, 96), (1200, 3000)):
            au, d2, d5, d10, npar = evaluer(A, y, test, cache, epochs)
            print(f"{nom:>26} {cache:>6} {epochs:>7} {au:>7.3f} "
                  f"{100*d2:>6.0f}% {100*d5:>6.0f}% {100*d10:>7.0f}% {npar:>8}")
            resultats.append({"jeu": nom, "cache": cache, "epochs": epochs,
                              "auc": au, "det2": d2, "det5": d5, "det10": d10,
                              "params": npar})
    print("-" * 92)
    meilleur = max(resultats, key=lambda r: r["det2"])
    print(f"MEILLEUR a 2 % de collateral : {meilleur['jeu']} "
          f"cache={meilleur['cache']} epochs={meilleur['epochs']} "
          f"-> {100*meilleur['det2']:.0f} %")
    if a.sortie:
        Path(a.sortie).write_text(json.dumps(resultats, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
