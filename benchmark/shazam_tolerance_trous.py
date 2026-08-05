#!/usr/bin/env python3
"""Le « Shazam coranique » survit-il aux mots que l'ASR laisse tomber ?

QUESTION DE L'UTILISATEUR (2026-08-05) : « si je dis A B C D E F G et que l'algo
retrouve A D F G, est-ce qu'il gere que A et D sont separes par 1 mot et non
par 4 ? »

CE QUE LE CODE FAIT AUJOURD'HUI (`quran_verse_locator_service.dart`). La cle
d'index est `'$a$b$k'` : l'ECART FAIT PARTIE DE LA CLE. Une paire ne correspond
donc que si l'ecart est IDENTIQUE dans la requete et dans le texte. Des qu'un
mot manque entre deux mots retenus, l'ecart de la requete diminue et la paire
ne matche plus -- alors meme que les deux mots sont justes.

Second effet, moins visible et tout aussi grave : le vote est `p - i`, ou `i`
est l'index dans la REQUETE. Une suppression decale tous les `i` suivants, donc
les votes d'avant et d'apres le trou tombent sur DEUX decalages differents. Le
pic se divise au lieu de s'additionner.

⚠️ LE COMMENTAIRE DU CODE AFFIRME L'INVERSE : « assez grand pour survivre a 1-3
mots perdus/mal transcrits par l'ASR entre deux mots effectivement reconnus ».
Ce banc existe pour trancher par la mesure, pas par la lecture.

CE QU'IL MESURE. On prend de vrais versets, on simule ce que fait un ASR --
suppressions (mots avales) et substitutions (mots mal transcrits) -- et on
regarde si le verset est encore retrouve, avec quel score, au seuil de 0,45 du
code. Puis on compare a une variante TOLERANTE aux ecarts, pour chiffrer ce
qu'on gagnerait.
"""
import argparse
import json
import random
import re
import unicodedata
from collections import defaultdict
from pathlib import Path

BASE = Path(__file__).parent
INDEX = BASE.parent / "app" / "assets" / "data" / "quran_search_index.json"

MAX_GAP = 4
MAX_OCC = 60
SEUIL = 0.45


def charger():
    d = json.loads(INDEX.read_text(encoding="utf-8"))
    versets, plat = [], []
    for v in d["verses"]:
        mots = v["w"]
        versets.append({"s": v["s"], "a": v["a"], "w": mots, "d": len(plat)})
        plat.extend(mots)
    return versets, plat


def index_paires(plat, tolerant=False):
    """`tolerant=False` reproduit le Dart : l'ecart est dans la cle.

    `tolerant=True` retire l'ecart de la cle -- la paire devient « ces deux
    mots apparaissent a moins de MAX_GAP l'un de l'autre », sans exiger la
    meme distance des deux cotes. On garde alors l'ecart en VALEUR, pour que
    le vote de decalage puisse en tenir compte."""
    idx = defaultdict(list)
    n = len(plat)
    for i in range(n):
        for k in range(1, min(MAX_GAP, n - 1 - i) + 1):
            cle = f"{plat[i]}{plat[i+k]}{k}" if not tolerant else f"{plat[i]}|{plat[i+k]}"
            idx[cle].append((i, k))
    return {c: p for c, p in idx.items() if len(p) <= MAX_OCC}


def verset_a(versets, pos):
    lo, hi = 0, len(versets) - 1
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if versets[mid]["d"] <= pos:
            lo = mid
        else:
            hi = mid - 1
    return versets[lo]


def localiser(mots_requete, idx, versets, plat, tolerant=False, fenetre=0):
    """`fenetre` > 0 : le vote n'exige plus l'egalite STRICTE du decalage.

    POURQUOI. Le decalage est `p - i`, ou `i` est l'index dans la REQUETE. Un
    mot avale par l'ASR decale tous les `i` suivants d'une unite : les votes
    d'avant et d'apres le trou tombent alors sur deux decalages DIFFERENTS, et
    le pic se divise au lieu de s'additionner. Additionner les votes sur une
    petite fenetre de decalages consecutifs recolle ces morceaux.

    La fenetre reste petite (quelques unites) : elle doit absorber quelques
    suppressions, pas autoriser deux zones eloignees du Coran a voter ensemble
    -- ce serait rendre a l'algorithme le defaut qu'il a ete ecrit pour
    supprimer."""
    votes = defaultdict(int)
    essais = 0
    n = len(mots_requete)
    for i in range(n):
        for k in range(1, min(MAX_GAP, n - 1 - i) + 1):
            essais += 1
            cle = (f"{mots_requete[i]}{mots_requete[i+k]}{k}" if not tolerant
                   else f"{mots_requete[i]}|{mots_requete[i+k]}")
            for (p, kk) in idx.get(cle, ()):
                # Le decalage estime : position du 1er mot de la requete dans
                # le texte. En mode tolerant on ne peut pas le connaitre
                # exactement (on ignore combien de mots ont ete avales avant
                # `i`), donc on vote pour `p - i` ET on accepte que le vote se
                # disperse -- c'est precisement ce que la mesure doit chiffrer.
                votes[p - i] += 1
    if not essais or not votes:
        return None, 0.0
    if fenetre > 0:
        # La fenetre sert a TROUVER le pic, pas a le situer. Sommer les votes
        # de d0 a d0+fenetre puis rapporter `d0` ferait tomber jusqu'a 4 mots
        # AVANT le vrai debut -- donc parfois sur le verset precedent. Mesure :
        # 98 % -> 92 % sur transcription parfaite, une perte gratuite.
        # On garde donc la fenetre pour le CHOIX, et on rapporte le decalage
        # qui porte le plus de votes a l'interieur.
        cumul = {d0: sum(votes.get(d0 + j, 0) for j in range(fenetre + 1))
                 for d0 in votes}
        d0 = max(cumul, key=lambda d: cumul[d])
        v = cumul[d0]
        dec = max(range(d0, d0 + fenetre + 1), key=lambda d: votes.get(d, 0))
    else:
        dec, v = max(votes.items(), key=lambda e: e[1])
    if dec < 0 or dec >= len(plat):
        return None, 0.0
    return verset_a(versets, dec), v / essais


def abimer(mots, p_suppr, p_subst, rng, lexique):
    """Simule une sortie ASR : mots avales, mots mal transcrits."""
    out = []
    for m in mots:
        r = rng.random()
        if r < p_suppr:
            continue
        if r < p_suppr + p_subst:
            out.append(rng.choice(lexique))
        else:
            out.append(m)
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--essais", type=int, default=300)
    p.add_argument("--min-mots", type=int, default=5)
    p.add_argument("--graine", type=int, default=0)
    a = p.parse_args()

    versets, plat = charger()
    print(f"index : {len(versets)} versets, {len(plat)} mots")
    idx_strict = index_paires(plat, tolerant=False)
    idx_tol = index_paires(plat, tolerant=True)
    print(f"paires retenues : strict {len(idx_strict)}, tolerant {len(idx_tol)}\n")

    rng = random.Random(a.graine)
    lexique = list({m for m in plat if len(m) > 2})
    candidats = [v for v in versets if len(v["w"]) >= a.min_mots]

    scenarios = [
        ("parfait (aucune erreur)", 0.0, 0.0),
        ("1 mot sur 10 avale", 0.10, 0.0),
        ("1 mot sur 5 avale", 0.20, 0.0),
        ("1 mot sur 10 mal transcrit", 0.0, 0.10),
        ("1 sur 10 avale + 1 sur 10 mal transcrit", 0.10, 0.10),
    ]
    print(f"{'scenario':<40} {'STRICT (code)':>16} {'ECART LIBRE':>16} "
          f"{'+ FENETRE':>16}")
    print("-" * 92)
    for nom, ps, pt in scenarios:
        res = {}
        for mode, idx in (("strict", idx_strict), ("tolerant", idx_tol),
                          ("tol+fen", idx_tol)):
            bons = scores = n = 0
            r = random.Random(a.graine)
            for _ in range(a.essais):
                v = r.choice(candidats)
                req = abimer(v["w"], ps, pt, r, lexique)
                if len(req) < 2:
                    continue
                n += 1
                trouve, sc = localiser(
                    req, idx, versets, plat,
                    tolerant=(mode in ("tolerant", "tol+fen")),
                    fenetre=(4 if mode == "tol+fen" else 0))
                scores += sc
                if (trouve and sc >= SEUIL
                        and trouve["s"] == v["s"] and trouve["a"] == v["a"]):
                    bons += 1
            res[mode] = (100 * bons / max(1, n), scores / max(1, n))
        print(f"{nom:<40} {res['strict'][0]:>6.0f} % ({res['strict'][1]:.2f})"
              f" {res['tolerant'][0]:>8.0f} % ({res['tolerant'][1]:.2f})"
              f" {res['tol+fen'][0]:>8.0f} % ({res['tol+fen'][1]:.2f})")
    print("-" * 92)
    print(f"« retrouve » = bon verset ET score >= {SEUIL} (le seuil du code).")


if __name__ == "__main__":
    main()
