#!/usr/bin/env python3
"""Inventaire mot par mot des non-verts, avec forced/free/secours/2e buffer.

PIEGE PAYE (2026-07-29) : une premiere version de ce script utilisait UNE seule
regex geante pour extraire tous les champs d'une ligne [GOP]. Elle exigeait
`normGop=` juste apres `gop=` -- or ce champ n'est ecrit QUE si
`normGop != r.gop` (recitation_provider.dart:3382, conditionnel). Toute ligne
ou les deux valeurs coincidaient (le cas le plus frequent pour un mot correct)
ne matchait plus DU TOUT, et le mot disparaissait silencieusement de
l'inventaire -- classe a tort comme "saute" alors qu'il etait juge correct.
Verifie : mot=16 de la passe 1 (v24) etait affiche "SAUTE/absent" alors que le
log dit noir sur blanc `WordStatus.correct`.

`taux_non_verts.py` (celui utilise toute la journee pour les agregats) n'a PAS
ce defaut : il extrait CHAQUE champ avec sa propre regex ciblee sur la meme
ligne, jamais une regex unique qui doit tout capturer d'un coup. Ce script
reprend la meme methode.
"""
import re
import sys
sys.path.insert(0, "benchmark")
from taux_non_verts import derniere_recitation


def inventaire(chemin, borne=98):
    T = open(chemin, encoding="utf-8", errors="replace").read().splitlines()
    L = T[derniere_recitation(T):]

    mots = {}   # index -> dict, ECRASE par chaque nouvelle ligne (= dernier etat)
    nj = set()
    secours_tentatives = {}
    secours_reussis = {}

    for l in L:
        m_idx = re.search(r'\[GOP\] mot=(\d+) "([^"]*)"', l)
        if m_idx:
            k = int(m_idx.group(1))
            if k >= borne:
                continue
            if "NON JUG" in l:
                nj.add(k)
                continue
            # Chaque champ a sa PROPRE regex, independante des autres.
            forced = re.search(r"forced=(-?[\d.]+)", l)
            free = re.search(r"free=(-?[\d.]+)", l)
            gopv = re.search(r"\bgop=(-?[\d.]+)", l)
            entendu = re.search(r'entendu="([^"]*)"', l)
            src = re.search(r"src=(\S+)", l)
            statut = re.search(r"WordStatus\.(\w+) \(lock=(\w+)", l)
            if statut:
                mots[k] = dict(
                    attendu=m_idx.group(2),
                    entendu=entendu.group(1) if entendu else "?",
                    forced=forced.group(1) if forced else "?",
                    free=free.group(1) if free else "?",
                    gop=gopv.group(1) if gopv else "?",
                    src=src.group(1) if src else "?",
                    statut=statut.group(1),
                    lock=statut.group(2),
                )
            continue
        m_sec = re.search(r"SECOURS.*mot=(\d+)", l)
        if m_sec:
            k = int(m_sec.group(1))
            if k < borne:
                secours_reussis[k] = secours_reussis.get(k, 0) + 1
            continue
        m_zf = re.search(r"ZERO FRAME mot=(\d+)", l)
        if m_zf:
            k = int(m_zf.group(1))
            if k < borne:
                secours_tentatives[k] = secours_tentatives.get(k, 0) + 1

    return mots, nj, secours_tentatives, secours_reussis


def afficher(chemin, borne=98):
    mots, nj, tent, reuss = inventaire(chemin, borne)
    verts = {k for k, v in mots.items() if v["statut"] == "correct" and v["lock"] == "true"}
    non_verts = sorted(set(range(borne)) - verts)
    print(f"{'mot':>4} {'attendu':<18} {'entendu':<18} {'gop':>6} {'forced':>7} "
          f"{'free':>7} {'statut':<10} {'lock':<5} {'src':<6} {'ZF':>3} {'secours':>7}")
    for k in non_verts:
        if k in mots:
            v = mots[k]
            print(f"{k:>4} {v['attendu']:<18} {v['entendu']:<18} {v['gop']:>6} "
                  f"{v['forced']:>7} {v['free']:>7} {v['statut']:<10} {v['lock']:<5} "
                  f"{v['src']:<6} {tent.get(k, 0):>3} {reuss.get(k, 0):>7}")
        elif k in nj:
            print(f"{k:>4} {'?':<18} {'NON JUGE':<18} {'?':>6} {'-':>7} {'-':>7} "
                  f"{'non_juge':<10} {'-':<5} {'-':<6} {tent.get(k, 0):>3} {reuss.get(k, 0):>7}")
        else:
            print(f"{k:>4} {'?':<18} {'SAUTE/absent':<18} {'?':>6} {'-':>7} {'-':>7} "
                  f"{'saute':<10} {'-':<5} {'-':<6} {tent.get(k, 0):>3} {reuss.get(k, 0):>7}")
    return len(non_verts), borne


if __name__ == "__main__":
    for p in sys.argv[1:]:
        print(f"\n{'=' * 100}\n{p}\n{'=' * 100}")
        n, b = afficher(p)
        print(f"-> {n}/{b} = {n / b * 100:.2f} %")
