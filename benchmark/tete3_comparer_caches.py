#!/usr/bin/env python3
"""Deux resumes d'etat d'encodeur se valent-ils, ou l'un bat-il vraiment l'autre ?

POURQUOI CE SCRIPT PLUTOT QU'UNE LECTURE DES DEUX CHIFFRES.

`det@2 % de collateral` se lit sur ~149 fautes du jeu de test : UNE faute vaut
0,67 point. Un ecart de 11 points, c'est 16 fautes -- assez peu pour venir du
tirage. Le projet a deja publie un « +48,6 % » qui s'est revele valoir
+0,1 point [-4,7 ; +3,7] une fois reechantillonne, avec 51 % de victoires : du
bruit pur presente comme un resultat.

CE QUI EST REECHANTILLONNE, ET POURQUOI CE N'EST PAS LA GRAINE.

Une tentative precedente a fait varier une graine externe : sans effet, parce
que `entrainer()` appelle `torch.manual_seed(0)` en interne -- la mesure etait
NULLE et l'a ete pendant une heure. On reechantillonne donc le JEU DE TEST
(bootstrap), qui est la vraie source d'incertitude ici : les memes modeles, le
meme entrainement, mais un tirage de mots different a chaque fois.

Le seuil de collateral est recalcule DANS chaque tirage, sur les corrects de ce
tirage : autrement on compterait les fautes d'un echantillon avec le seuil d'un
autre, ce qui fabrique de la variance qui n'existe pas.

LECTURE. L'ecart n'est concluant que si l'intervalle a 95 % ne contient pas 0
ET si le taux de victoires s'ecarte franchement de 50 %.
"""
import argparse
import sys
from pathlib import Path

import numpy as np
import torch

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from tete_ecart_canonique import entrainer  # noqa: E402


def scores_test(chemin, cache_unites, epochs):
    """Entraine la tete sur ce cache et rend les scores du jeu de TEST."""
    z = np.load(chemin)
    E, X, y, test = z["E"], z["X"], z["y"], z["test"]
    ok = np.isfinite(X).all(1) & (np.abs(X) < 1e6).all(1) & np.isfinite(E).all(1)
    E, X, y, test = E[ok], X[ok], y[ok], test[ok]
    A = np.hstack([E, X])
    ap, at = ~test, test
    mu, sd = A[ap].mean(0), A[ap].std(0) + 1e-6
    A = (A - mu) / sd
    poids = float((y[ap] == 0).sum() / max(1, (y[ap] == 1).sum()))
    torch.manual_seed(0)
    m, _, _ = entrainer(A[ap], y[ap], poids, epochs=epochs, cache=cache_unites)
    with torch.no_grad():
        s = m(torch.tensor(A[at], dtype=torch.float32)).squeeze(1).numpy()
    return s, y[at], int(ap.sum()), A.shape[1]


def detection(s, y, alpha):
    """Part des fautes au-dessus du quantile (1-alpha) des CORRECTS."""
    c, f = s[y == 0], s[y == 1]
    if len(c) == 0 or len(f) == 0:
        return float("nan")
    return float((f > np.quantile(c, 1.0 - alpha)).mean())


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--caches", nargs=2, required=True, metavar=("AVANT", "APRES"))
    p.add_argument("--noms", nargs=2, default=["avant", "apres"])
    p.add_argument("--cache-unites", type=int, default=128)
    p.add_argument("--epochs", type=int, default=3000)
    p.add_argument("--alpha", type=float, default=0.02)
    p.add_argument("--tirages", type=int, default=2000)
    a = p.parse_args()

    sA, yA, nA, dA = scores_test(a.caches[0], a.cache_unites, a.epochs)
    sB, yB, nB, dB = scores_test(a.caches[1], a.cache_unites, a.epochs)
    if len(yA) != len(yB) or not np.array_equal(yA, yB):
        raise SystemExit(
            "les deux caches n'ont pas le MEME jeu de test -- la comparaison "
            "serait sans objet (deux mesures sur deux populations)")

    print(f"{a.noms[0]:>14s} : {dA:5d} caracteristiques, {nA} exemples d'entrainement")
    print(f"{a.noms[1]:>14s} : {dB:5d} caracteristiques, {nB} exemples d'entrainement")
    print(f"test commun : {len(yA)} mots dont {int(yA.sum())} fautes "
          f"(1 faute = {100/max(1,yA.sum()):.2f} point)\n")

    dA0 = detection(sA, yA, a.alpha)
    dB0 = detection(sB, yB, a.alpha)
    print(f"  {a.noms[0]:>14s}  {100*dA0:5.1f} %")
    print(f"  {a.noms[1]:>14s}  {100*dB0:5.1f} %")
    print(f"  {'ecart brut':>14s}  {100*(dB0-dA0):+5.1f} points\n")

    rng = np.random.default_rng(0)
    n = len(yA)
    ecarts = np.empty(a.tirages)
    for t in range(a.tirages):
        i = rng.integers(0, n, n)
        ecarts[t] = detection(sB[i], yA[i], a.alpha) - detection(sA[i], yA[i], a.alpha)
    lo, hi = np.percentile(ecarts, [2.5, 97.5])
    victoires = float((ecarts > 0).mean())
    print(f"  bootstrap sur le jeu de test ({a.tirages} tirages)")
    print(f"    ecart median      {100*np.median(ecarts):+5.1f} points")
    print(f"    intervalle 95 %   [{100*lo:+.1f} ; {100*hi:+.1f}]")
    print(f"    victoires         {100*victoires:.0f} %\n")
    if lo > 0:
        print(f"  => {a.noms[1]} bat {a.noms[0]} : l'intervalle exclut 0.")
    elif hi < 0:
        print(f"  => {a.noms[1]} PERD contre {a.noms[0]} : l'intervalle exclut 0.")
    else:
        print("  => INDECIDABLE : l'intervalle contient 0, l'ecart observe est "
              "compatible avec le bruit d'echantillonnage.")


if __name__ == "__main__":
    main()
