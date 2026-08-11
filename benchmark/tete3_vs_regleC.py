#!/usr/bin/env python3
"""La tete 3 et la regle C sont-elles REDONDANTES ou COMPLEMENTAIRES ?

QUESTION DE L'UTILISATEUR (2026-08-05) : « adapte l'app pour juger avec tete 3,
ou c'est deux regles, je ne sais pas s'ils peuvent etre complementaires ».

C'est une question mesurable, et la reponse change ce qu'il faut coder :
  - si l'une CONTIENT l'autre, on remplace, et le code se simplifie ;
  - si elles attrapent des fautes DIFFERENTES, on combine, et le gain peut
    depasser le meilleur des deux.

CE QUI EST COMPARE, a budget de collateral EGAL (c'est la seule comparaison
honnete : signaler plus attrape mecaniquement plus).
  - regle C seule = `margeLettres`, c'est-a-dire EXACTEMENT ce que l'app
    utilise aujourd'hui pour peindre du rouge (Decideur.couleur :
    `margeLettres < seuilMargeRouge`) ;
  - tete 3 seule ;
  - UNION : l'une OU l'autre signale, chacune a un budget reduit pour que le
    total reste a 2 % -- sinon on comparerait 2 % contre 4 % ;
  - FUSION : une combinaison lineaire des deux scores, seuillee une seule fois.

Et surtout le RECOUVREMENT : parmi les fautes que la tete 3 attrape, combien la
regle C attrapait-elle deja ? C'est ce chiffre qui dit « redondant » ou
« complementaire », independamment de tout seuil.
"""
import argparse
import sys
from pathlib import Path

import numpy as np
import torch

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from tete_ecart_canonique import NOMS, detection_a_collateral  # noqa: E402
from balayage_tete3 import charger, evaluer  # noqa: E402
from tete3_par_paires import Tete  # noqa: E402


def seuil_pour_collateral(sc, alpha):
    """Score au-dessus duquel exactement `alpha` des CORRECTS se trouvent."""
    return float(np.quantile(sc, 1.0 - alpha))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--cache", required=True)
    p.add_argument("--cache-unites", type=int, default=128)
    p.add_argument("--epochs", type=int, default=3000)
    a = p.parse_args()

    E, X, y, test = charger([a.cache])
    ok = np.isfinite(X).all(1) & (np.abs(X) < 1e6).all(1) & np.isfinite(E).all(1)
    E, X, y, test = E[ok], X[ok], y[ok], test[ok]
    A = np.hstack([E, X])
    ap, at = ~test, test

    # ── Tete 3, entrainee exactement comme la version retenue ────────────────
    mu, sd = A[ap].mean(0), A[ap].std(0) + 1e-6
    An = (A - mu) / sd
    poids = float((y[ap] == 0).sum() / max(1, (y[ap] == 1).sum()))
    torch.manual_seed(0)
    from tete_ecart_canonique import entrainer
    m, npar, _ = entrainer(An[ap], y[ap], poids, epochs=a.epochs,
                           cache=a.cache_unites)
    with torch.no_grad():
        s_tete = m(torch.tensor(An[at], dtype=torch.float32)).squeeze(1).numpy()

    # ── Regle C = margeLettres. Plus elle est BASSE, plus c'est suspect :
    #    on prend l'oppose pour que « grand = suspect » dans les deux cas.
    i_alt = NOMS.index("gopC") if "gopC" in NOMS else None
    s_regle = -X[at][:, NOMS.index("gopC")]

    yt = y[at]
    f, c = yt == 1, yt == 0
    print(f"test : {c.sum()} mots corrects, {f.sum()} fautes\n")

    def det(s, alpha=0.02):
        tau = seuil_pour_collateral(s[c], alpha)
        return (s[f] > tau), tau

    for nom, s in (("regle C (ce que l'app utilise)", s_regle),
                   ("tete 3", s_tete)):
        pris, _ = det(s)
        print(f"  {nom:34s} {100*pris.mean():5.1f} % de detection a 2 %")

    # ── RECOUVREMENT : qui attrape quoi ? ────────────────────────────────────
    pr, _ = det(s_regle)
    pt, _ = det(s_tete)
    print(f"\n  RECOUVREMENT (a 2 % de collateral chacune)")
    print(f"    attrapees par les DEUX          : {int((pr & pt).sum()):4d}")
    print(f"    par la tete 3 SEULEMENT         : {int((~pr & pt).sum()):4d}")
    print(f"    par la regle C SEULEMENT        : {int((pr & ~pt).sum()):4d}")
    print(f"    ratees par les deux             : {int((~pr & ~pt).sum()):4d}")
    if pt.sum():
        print(f"    -> {100*(pr & pt).sum()/pt.sum():.0f} % de ce que la tete 3 "
              f"attrape etait DEJA vu par la regle C")

    # ── UNION a budget total de 2 % (1 % chacune) ────────────────────────────
    pr1, _ = det(s_regle, 0.01)
    pt1, _ = det(s_tete, 0.01)
    union = pr1 | pt1
    coll = ((s_regle[c] > seuil_pour_collateral(s_regle[c], 0.01)) |
            (s_tete[c] > seuil_pour_collateral(s_tete[c], 0.01))).mean()
    print(f"\n  UNION (1 % + 1 %)                 {100*union.mean():5.1f} % "
          f"de detection, collateral reel {100*coll:.1f} %")

    # ── FUSION : combinaison lineaire, un seul seuil ─────────────────────────
    zr = (s_regle - s_regle[c].mean()) / (s_regle[c].std() + 1e-9)
    zt = (s_tete - s_tete[c].mean()) / (s_tete[c].std() + 1e-9)
    print(f"\n  FUSION w*tete + (1-w)*regle, a 2 % de collateral :")
    best = (0, None)
    for w in (0.0, 0.25, 0.5, 0.75, 0.9, 1.0):
        sf = w * zt + (1 - w) * zr
        pris, _ = det(sf)
        d = pris.mean()
        print(f"    w={w:<5} {100*d:5.1f} %")
        if d > best[0]:
            best = (d, w)
    print(f"\n  MEILLEURE FUSION : {100*best[0]:.1f} % (w={best[1]})")


if __name__ == "__main__":
    main()
