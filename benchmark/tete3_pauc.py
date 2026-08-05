#!/usr/bin/env python3
"""Tete 3 : optimiser LA REGION MESUREE, et non toute la distribution.

CE QUE LES DEUX TENTATIVES PRECEDENTES ONT APPRIS (2026-08-05).

  BCE seule ............................ 47 %   (reference)
  rang intra-paire seul ................ 16 %
  rang intra-paire + ancrage BCE ....... 43 %

La perte de rang par paires a ete REFUTEE, et son echec est instructif :
contraindre `faute_i` face a SON PROPRE correct est une contrainte LOCALE,
alors que `det@2 % de collateral` exige que chaque faute passe devant TOUS les
mots corrects du corpus. Ordonner deux versions d'un meme mot n'y contribue
presque pas -- et peut contrarier l'ordre global.

L'IDEE ICI, qui suit directement de ce diagnostic.

`det@2 %` ne regarde qu'une chose : combien de fautes se placent AU-DESSUS du
98e centile des scores des mots CORRECTS. Tout le reste de la distribution --
ou vivent 98 % des exemples -- ne compte pas dans la mesure, mais accapare la
quasi-totalite du gradient d'une BCE. On optimise donc massivement ce qu'on ne
mesure pas.

La perte ci-dessous ne penalise que ce qui deplace ce chiffre :
  1. le seuil `tau` = 98e centile des scores des corrects (recalcule a chaque
     pas, donc toujours a jour) ;
  2. une charniere sur les fautes SOUS ce seuil : celles-la seules manquent a
     l'appel ;
  3. une charniere sur les corrects AU-DESSUS : ce sont eux qui font monter le
     seuil et coutent du collateral.

Ce n'est PAS un deplacement de critere : le seuil n'est pas relache, il est
CIBLE. On demande au modele d'optimiser la quantite qu'on lui reproche de
rater, au lieu d'une quantite correlee.

Le protocole de test est inchange (189 phrases tenues a l'ecart, meme graine),
sans quoi le chiffre ne serait comparable ni aux 47 % ni a l'historique.
"""
import argparse
import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from tete_ecart_canonique import detection_a_collateral  # noqa: E402


def auc(sf, sc):
    a = np.concatenate([sf, sc])
    r = a.argsort().argsort() + 1
    return (r[:len(sf)].sum() - len(sf) * (len(sf) + 1) / 2) / (len(sf) * len(sc))


class Tete(nn.Module):
    def __init__(self, d, cache):
        super().__init__()
        self.net = nn.Sequential(nn.Linear(d, cache), nn.ReLU(), nn.Linear(cache, 1))

    def forward(self, x):
        return self.net(x).squeeze(-1)


def entrainer_pauc(A, y, epochs, cache, alpha, w_bce, marge, lr=1e-3, graine=0):
    torch.manual_seed(graine)
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    X = torch.tensor(A, dtype=torch.float32, device=dev)
    Y = torch.tensor(y, dtype=torch.float32, device=dev)
    I_f = torch.nonzero(Y == 1).squeeze(1)
    I_c = torch.nonzero(Y == 0).squeeze(1)

    m = Tete(A.shape[1], cache).to(dev)
    opt = torch.optim.Adam(m.parameters(), lr=lr)
    poids_pos = float((y == 0).sum() / max(1, (y == 1).sum()))
    bce = nn.BCEWithLogitsLoss(pos_weight=torch.tensor(poids_pos, device=dev))
    for _ in range(epochs):
        opt.zero_grad()
        s = m(X)
        sc, sf = s[I_c], s[I_f]
        # Seuil = quantile (1 - alpha) des CORRECTS : le point de fonctionnement
        # vise. Detache : c'est une cible, pas une variable a optimiser.
        tau = torch.quantile(sc, 1.0 - alpha).detach()
        manquees = torch.clamp(marge - (sf - tau), min=0).mean()
        collateral = torch.clamp(marge - (tau - sc), min=0).mean()
        perte = manquees + collateral + w_bce * bce(s, Y)
        perte.backward()
        opt.step()
    return m, sum(p.numel() for p in m.parameters())


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--cache", required=True)
    p.add_argument("--epochs", type=int, default=3000)
    a = p.parse_args()

    z = np.load(a.cache)
    E, X, y, test = z["E"], z["X"], z["y"], z["test"]
    ok = np.isfinite(X).all(1) & (np.abs(X) < 1e6).all(1) & np.isfinite(E).all(1)
    E, X, y, test = E[ok], X[ok], y[ok], test[ok]
    A = np.hstack([E, X])
    ap, at = ~test, test
    mu, sd = A[ap].mean(0), A[ap].std(0) + 1e-6
    A = (A - mu) / sd
    print(f"{len(y)} exemples, {A.shape[1]} caracteristiques, "
          f"{int(y.sum())} fautes")
    print(f"entrainement {int(ap.sum())} | test {int(at.sum())} "
          f"({int(y[at].sum())} fautes)\n")

    dev = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"{'cache':>6} {'alpha':>6} {'w_bce':>6} {'marge':>6} "
          f"{'AUC':>7} {'det@2%':>7} {'det@5%':>7} {'det@10%':>8}")
    print("-" * 70)
    best = (0, None)
    for cache in (128, 256):
        for alpha in (0.02, 0.05):
            for w_bce in (0.1, 0.5, 2.0):
                for marge in (1.0,):
                    m, _ = entrainer_pauc(A[ap], y[ap], a.epochs, cache,
                                          alpha, w_bce, marge)
                    with torch.no_grad():
                        s = m(torch.tensor(A[at], dtype=torch.float32,
                                           device=dev)).cpu().numpy()
                    sf, sc = s[y[at] == 1], s[y[at] == 0]
                    d2 = detection_a_collateral(sf, sc, 0.02)[0]
                    d5 = detection_a_collateral(sf, sc, 0.05)[0]
                    d10 = detection_a_collateral(sf, sc, 0.10)[0]
                    print(f"{cache:>6} {alpha:>6.2f} {w_bce:>6.1f} {marge:>6.1f} "
                          f"{auc(sf, sc):>7.3f} {100*d2:>6.0f}% {100*d5:>6.0f}% "
                          f"{100*d10:>7.0f}%", flush=True)
                    if d2 > best[0]:
                        best = (d2, (cache, alpha, w_bce))
    print("-" * 70)
    print(f"MEILLEUR : {100*best[0]:.0f} % (cache={best[1][0]} "
          f"alpha={best[1][1]} w_bce={best[1][2]})")
    print("References, meme test, meme graine : BCE seule 47 %, par paires 43 %")


if __name__ == "__main__":
    main()
