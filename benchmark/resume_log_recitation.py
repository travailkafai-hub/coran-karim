"""Résumé lisible d'un log de récitation : mot attendu / mot entendu, au PREMIER
jugement — puis ce qu'il est devenu.

POURQUOI LE PREMIER JUGEMENT (demande utilisateur 2026-07-25) : « sur un mot
j'ai effectué exprès une erreur de harakat, c'était jaune au début mais repassé
vert ». La question « le système a-t-il vu ma faute ? » se joue sur la PREMIÈRE
fois qu'il entend le mot. Le verdict final, lui, arrive souvent après une
correction (le réciteur a redit le mot correctement) — il ne dit donc rien sur
la détection initiale. Les deux colonnes sont donc affichées séparément.

Le log mélange plusieurs sources (natif Kotlin, Dart, GOP, alignement) ; ici on
ne garde que ce qui répond à cette question.

USAGE
    python3 benchmark/resume_log_recitation.py <log> [--tout] [--csv fichier]

    (sans option : seulement les mots dont le premier verdict n'est pas
     `correct`, ou dont le verdict a changé — c'est là que se trouve
     l'information. `--tout` affiche les 121 mots.)
"""
import argparse
import csv
import re
import sys
from collections import OrderedDict

NEG = ("error", "unclear", "skipped")


def parse(path):
    """Retourne {index: {txt, events[], corrections[]}} dans l'ordre d'apparition."""
    words = OrderedDict()
    corrections = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        if "[GOP]" in line:
            mi = re.search(r'mot=(\d+) "([^"]*)"', line)
            mv = re.search(r"-> WordStatus\.(\w+)", line)
            if not (mi and mv):
                continue
            me = re.search(r'entendu="([^"]*)"', line)
            ms = re.search(r"src=(\w+)", line)
            mg = re.search(r"gop=(-?[\d.]+)", line)
            mn = re.search(r"normGop=(-?[\d.]+)", line)
            ml = re.search(r"lock=(\w+),", line)
            mf = re.search(r"final=(\w+)\)", line)
            i = int(mi.group(1))
            w = words.setdefault(i, {"txt": mi.group(2), "ev": []})
            w["ev"].append({
                "t": line[11:23],
                "v": mv.group(1),
                "heard": me.group(1) if me else "",
                "src": ms.group(1) if ms else "?",
                "gop": mn.group(1) if mn else (mg.group(1) if mg else ""),
                "lock": bool(ml and ml.group(1) == "true"),
                "final": bool(mf and mf.group(1) == "true"),
            })
        elif "wordFailed déclenché" in line:
            m = re.search(r"wordIndex\(global\)=(\d+)", line)
            if m:
                corrections.setdefault(int(m.group(1)), []).append(line[11:23])
    return words, corrections


SYMB = {"correct": "vert", "unclear": "ORANGE", "error": "ROUGE",
        "skipped": "SAUTE", "pending": "-", "current": "-"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--tout", action="store_true",
                    help="afficher aussi les mots corrects du premier coup")
    ap.add_argument("--csv")
    args = ap.parse_args()

    words, corrections = parse(args.log)
    if not words:
        print("Aucun jugement [GOP] dans ce log.")
        return 1

    rows = []
    for i, w in words.items():
        first, last = w["ev"][0], w["ev"][-1]
        rows.append({
            "mot": i,
            "attendu": w["txt"],
            "entendu_1er": first["heard"],
            "verdict_1er": first["v"],
            "gop_1er": first["gop"],
            "src_1er": first["src"],
            "verdict_final": last["v"],
            "entendu_final": last["heard"],
            "passes": len(w["ev"]),
            "corrections": len(corrections.get(i, [])),
            "heure_1er": first["t"],
        })

    if args.csv:
        with open(args.csv, "w", newline="", encoding="utf-8") as f:
            wr = csv.DictWriter(f, fieldnames=list(rows[0]))
            wr.writeheader()
            wr.writerows(rows)
        print(f"CSV écrit : {args.csv}  ({len(rows)} mots)")

    shown = [r for r in rows
             if args.tout or r["verdict_1er"] in NEG
             or r["verdict_1er"] != r["verdict_final"]]

    print(f"\n{len(rows)} mots jugés — {len(shown)} affichés "
          f"({'tous' if args.tout else 'seulement ceux avec un verdict négatif ou qui a changé'})\n")
    print(f"{'mot':>4s} {'attendu':<20s} {'ENTENDU (1re fois)':<24s} "
          f"{'1er':<7s} {'gop':>7s} {'src':<6s} {'final':<7s} {'p':>2s} {'corr':>4s}")
    print("-" * 104)
    for r in shown:
        flag = ""
        if r["verdict_1er"] in NEG and r["verdict_final"] == "correct":
            flag = "  <<< signale puis repasse VERT"
        elif r["verdict_1er"] == "correct" and r["verdict_final"] in NEG:
            flag = "  <<< valide puis repasse NEGATIF (regression)"
        print(f"{r['mot']:>4d} {r['attendu']:<20s} {r['entendu_1er']:<24s} "
              f"{SYMB.get(r['verdict_1er'], r['verdict_1er']):<7s} {r['gop_1er']:>7s} "
              f"{r['src_1er']:<6s} {SYMB.get(r['verdict_final'], r['verdict_final']):<7s} "
              f"{r['passes']:>2d} {r['corrections']:>4d}{flag}")

    n_neg1 = sum(1 for r in rows if r["verdict_1er"] in NEG)
    n_rattrape = sum(1 for r in rows if r["verdict_1er"] in NEG and r["verdict_final"] == "correct")
    n_regress = sum(1 for r in rows if r["verdict_1er"] == "correct" and r["verdict_final"] in NEG)
    print(f"\nPremier jugement négatif : {n_neg1}/{len(rows)}")
    print(f"  dont repassés verts ensuite : {n_rattrape}")
    print(f"Validés du premier coup puis repassés négatifs : {n_regress}")
    print(f"Corrections déclenchées : {sum(len(v) for v in corrections.values())}")
    print("\nRappel de lecture : un mot « signalé puis repassé vert » n'est PAS")
    print("forcément un faux positif -- c'est souvent la correction qui a marché")
    print("(tu as redit le mot juste). Ce qui est anormal, c'est la ligne")
    print("« validé puis repassé négatif ».")
    return 0


if __name__ == "__main__":
    sys.exit(main())
