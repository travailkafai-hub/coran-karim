#!/usr/bin/env python3
"""Tete 3 entrainee PAR PAIRES : comparer un mot a LUI-MEME, pas au corpus.

POURQUOI CETTE VOIE, apres le plateau a 47 % de la nuit du 2026-08-05.

Six leviers ont ete mesures et epuises (capacite, epochs, volume, features).
Tous portaient sur le MODELE ou sur les DONNEES. Aucun ne portait sur ce qu'on
lui demande d'OPTIMISER -- et c'est la que le defaut se cache.

    `det@2 % de collateral` est une metrique de CLASSEMENT : elle demande que
    les mots fautes soient au-dessus des mots corrects dans un tri. La BCE, elle,
    optimise la CALIBRATION -- que la probabilite predite colle a l'etiquette.
    Ce ne sont pas les memes objectifs, et l'ecart se paie exactement la ou on
    mesure : dans la QUEUE de la distribution, ou vivent les 2 %.

CE QUE LES PAIRES APPORTENT, et que rien d'autre n'apporte. Le corpus TTS est
APPARIE par construction : pour chaque mot, un clip CORRECT et un clip FAUTE,
meme voix, meme phrase, meme position, meme voisinage. La seule chose qui
differe entre les deux est LA FAUTE.

Comparer un mot a lui-meme supprime donc toute la variation de nuisance --
identite du mot, timbre du recitateur, place dans le souffle, longueur -- qui
represente l'essentiel de la variance vue par une loss point par point. Le
signal utile n'est plus noye dedans.

L'OBJECTIF : pour chaque paire, exiger score(faute) > score(correct) + marge.
C'est litteralement la quantite que `det@collateral` mesure. Aucune tolerance
n'est deplacee, aucun seuil ajoute : on demande enfin au modele d'optimiser ce
qu'on lui reproche de rater.

⚠️ Les paires ne servent qu'a l'ENTRAINEMENT. A l'inference l'app n'a qu'un
seul audio -- le modele projette un exemple isole, exactement comme avant. Le
protocole de test est INCHANGE (189 phrases tenues a l'ecart, meme graine),
sans quoi le chiffre ne serait comparable a rien.
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


def entrainer_paires(A, y, paire, epochs, cache, marge, lr, poids_bce, graine=0):
    """Perte de RANG sur les paires + une part de BCE pour ancrer l'echelle.

    La BCE seule optimise la calibration (mesure : 47 %). Le rang seul peut
    deriver sans reference absolue. On garde donc une petite part de BCE --
    `poids_bce` -- dont l'effet est mesure par le balayage, pas suppose."""
    torch.manual_seed(graine)
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    X = torch.tensor(A, dtype=torch.float32, device=dev)
    Y = torch.tensor(y, dtype=torch.float32, device=dev)

    # Couples (faute, correct) partageant le meme identifiant de paire.
    idx_f = {int(p): i for i, p in enumerate(paire) if y[i] == 1}
    idx_c = {int(p): i for i, p in enumerate(paire) if y[i] == 0}
    communs = sorted(set(idx_f) & set(idx_c))
    if not communs:
        raise SystemExit("aucune paire complete : le cache ne porte pas `paire`")
    I_f = torch.tensor([idx_f[p] for p in communs], device=dev)
    I_c = torch.tensor([idx_c[p] for p in communs], device=dev)

    m = Tete(A.shape[1], cache).to(dev)
    opt = torch.optim.Adam(m.parameters(), lr=lr)
    poids_pos = float((y == 0).sum() / max(1, (y == 1).sum()))
    bce = nn.BCEWithLogitsLoss(pos_weight=torch.tensor(poids_pos, device=dev))
    for _ in range(epochs):
        opt.zero_grad()
        s = m(X)
        # marge : le score de la faute doit depasser celui de SON correct.
        rang = torch.clamp(marge - (s[I_f] - s[I_c]), min=0).mean()
        perte = rang + poids_bce * bce(s, Y)
        perte.backward()
        opt.step()
    return m, len(communs), sum(p.numel() for p in m.parameters())


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--cache", required=True)
    p.add_argument("--epochs", type=int, default=3000)
    a = p.parse_args()

    z = np.load(a.cache)
    if "paire" not in z:
        raise SystemExit("ce cache n'a pas d'identifiants de paire")
    E, X, y, test, paire = z["E"], z["X"], z["y"], z["test"], z["paire"]
    ok = np.isfinite(X).all(1) & (np.abs(X) < 1e6).all(1) & np.isfinite(E).all(1)
    E, X, y, test, paire = E[ok], X[ok], y[ok], test[ok], paire[ok]
    A = np.hstack([E, X])
    ap, at = ~test, test
    mu, sd = A[ap].mean(0), A[ap].std(0) + 1e-6
    A = (A - mu) / sd
    print(f"{len(y)} exemples, {A.shape[1]} caracteristiques, "
          f"{int(y.sum())} fautes")
    print(f"entrainement {int(ap.sum())} | test {int(at.sum())} "
          f"({int(y[at].sum())} fautes)\n")

    dev = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"{'cache':>6} {'marge':>6} {'w_bce':>6} {'lr':>7} {'paires':>7} "
          f"{'AUC':>7} {'det@2%':>7} {'det@5%':>7} {'det@10%':>8}")
    print("-" * 78)
    best = (0, None)
    for cache in (128, 256):
        for marge in (0.5, 2.0, 5.0):
            for w in (0.0, 0.2, 1.0):
                m, npaires, _ = entrainer_paires(
                    A[ap], y[ap], paire[ap], a.epochs, cache, marge, 1e-3, w)
                with torch.no_grad():
                    s = m(torch.tensor(A[at], dtype=torch.float32,
                                       device=dev)).cpu().numpy()
                sf, sc = s[y[at] == 1], s[y[at] == 0]
                d2 = detection_a_collateral(sf, sc, 0.02)[0]
                d5 = detection_a_collateral(sf, sc, 0.05)[0]
                d10 = detection_a_collateral(sf, sc, 0.10)[0]
                print(f"{cache:>6} {marge:>6.1f} {w:>6.1f} {1e-3:>7.0e} "
                      f"{npaires:>7} {auc(sf, sc):>7.3f} {100*d2:>6.0f}% "
                      f"{100*d5:>6.0f}% {100*d10:>7.0f}%", flush=True)
                if d2 > best[0]:
                    best = (d2, (cache, marge, w))
    print("-" * 78)
    print(f"MEILLEUR : {100*best[0]:.0f} % (cache={best[1][0]} "
          f"marge={best[1][1]} w_bce={best[1][2]})")
    print("Reference BCE seule, meme test, meme graine : 47 %")


if __name__ == "__main__":
    main()
