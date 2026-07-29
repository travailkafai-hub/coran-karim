#!/usr/bin/env python3
"""Verdict du test d'anneau : le secours atteint-il enfin les mots enlises ?

POURQUOI CE BANC (2026-07-29). Le taux de non verts ne suffit PAS a conclure sur
ce test : il varie deja de 4 a 11 % entre passes propres, et le decrochage est
un evenement binaire qui frappe environ une passe sur trois toutes versions
confondues. Trois passes ne peuvent donc ni prouver ni refuter un effet a elles
seules -- il faut lire le MECANISME, pas seulement le resultat.

Ce que ce script confronte, pour chaque session :

  secours IMPOSSIBLE   la fenetre demandee etait hors de l'anneau. C'est
                       EXACTEMENT ce que l'elargissement 30 s -> 120 s doit
                       faire disparaitre. S'ils tombent a zero, le palliatif
                       agit bien la ou on l'attendait.
  secours REUSSIS      un mot ampute effectivement reconstitue.
  ecart max reclame    de combien le secours remontait dans le passe (ms). Sur
                       la passe decrochee du matin : 85 s, pour un anneau de
                       30 s -- d'ou les six echecs.
  enlisement max       plus longue serie de ZERO FRAME sur un MEME mot. C'est
                       la cause de fond, que l'anneau ne corrige PAS : si elle
                       reste elevee alors que les IMPOSSIBLE ont disparu, le
                       test a prouve la chaine causale sans la traiter.

Lecture du verdict :
  IMPOSSIBLE -> 0  ET  decrochages -> 0   la chaine causale est confirmee
  IMPOSSIBLE -> 0  ET  decrochages restent  l'anneau n'etait pas le maillon
  IMPOSSIBLE > 0                          l'elargissement n'a pas pris effet

USAGE
    python3 benchmark/verdict_anneau.py <dossier_session> [...]
"""
import re
import sys
import os
import glob
import collections


def analyser(chemin):
    txt = open(chemin, encoding="utf-8", errors="replace").read()
    build = re.search(r"build=(\S+)", txt)

    impossible = len(re.findall(r"secours mot=\d+ IMPOSSIBLE", txt))
    reussis = len(re.findall(r"SECOURS \(", txt))

    # Ecart entre l'instant reclame et l'audio deja recu, au moment de l'appel.
    ecarts = [
        int(dispo) - int(fin)
        for _, fin, dispo in re.findall(
            r"secours mot=(\d+) fenetre mot=\[\d+,(\d+)\)ms .*?dispo=(\d+)ms", txt
        )
    ]

    # Enlisement : plus longue serie de ZERO FRAME sur un meme mot.
    zf = collections.Counter(int(m) for m in re.findall(r"ZERO FRAME mot=(\d+)", txt))

    resync = len(re.findall(r"RESYNC", txt))

    return dict(
        build=build.group(1) if build else "?",
        impossible=impossible,
        reussis=reussis,
        ecart_max=max(ecarts) if ecarts else 0,
        enlisement=zf.most_common(1)[0] if zf else (0, 0),
        resync=resync,
    )


if __name__ == "__main__":
    cibles = sys.argv[1:] or sorted(glob.glob("benchmark/recettes/*/"))
    print(f"{'session':<24}{'build':<26}{'IMPOSS':>7}{'reussis':>8}"
          f"{'ecart_max':>11}{'enlisement':>13}{'resync':>7}")
    for d in cibles:
        p = os.path.join(d, "session.log")
        if not os.path.exists(p) or os.path.getsize(p) == 0:
            continue
        r = analyser(p)
        mot, n = r["enlisement"]
        print(f"{os.path.basename(d.rstrip('/')):<24}{r['build']:<26}"
              f"{r['impossible']:>7}{r['reussis']:>8}"
              f"{r['ecart_max'] / 1000:>10.1f}s{f'mot{mot}x{n}':>13}{r['resync']:>7}")
