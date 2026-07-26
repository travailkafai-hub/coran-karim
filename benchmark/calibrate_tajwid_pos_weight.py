"""Calcule un pos_weight par classe pour la BCE multi-label de la tete tajwid
(2026-07-24, idee utilisateur : attenuer l'impact des classes tres frequentes
-- ham_wasl, madda_normal -- dans l'apprentissage des classes rares/en
chevauchement, cf. finetune_dual_head.py::_tajwid_loss).

Methode : pos_weight[c] = min(CAP, sqrt(frames_negatifs[c] / frames_positifs[c])).
PREMIERE VERSION (2026-07-24, inverse frequence brute plafonnee a 5.0) :
mesure invalidante -- TOUTES les 19 classes depassent 5.0 de ratio neg/pos
(aucune classe n'occupe plus de 13.7% des frames en multi-label, la rarete
"relative" y est la norme, pas l'exception). Le plafond saturait donc
partout : pos_weight=5.0 UNIFORME sur toutes les classes, ce qui revient a
un simple facteur d'echelle global -- AUCUNE differenciation entre classes,
alors que c'est precisement ce qui etait demande (attenuer ham_wasl/
madda_normal, tres frequentes, sans laisser les classes rares dominer).
Racine carree : compresse l'echelle (une classe 100x plus rare qu'une autre
recoit un poids 10x plus grand, pas 100x) -- les ecarts relatifs entre
classes redeviennent visibles sans que les plus rares (waqf_lazim : 318
frames positives sur ~10,5M, 22 occurrences dans tout le Coran) n'ecrasent
l'entrainement des autres.

Usage :
  SITE="benchmark/.venv_nemo/lib/python3.14/site-packages"
  PYTHONPATH="$PWD/$SITE" /usr/bin/python3.14 calibrate_tajwid_pos_weight.py \
      nemo_manifests_dual/tajwid_frame_spans_train.jsonl \
      --out nemo_manifests_dual/tajwid_pos_weight.json
"""
import json
import argparse
from pathlib import Path

RULE_CLASSES = [
    "madda_necessary", "madda_obligatory", "madda_permissible", "madda_normal",
    "ghunnah", "ikhafa", "ikhafa_shafawi", "idgham_ghunnah", "idgham_shafawi",
    "iqlab", "idgham_wo_ghunnah", "idgham_mutajanisayn", "idgham_mutaqaribayn",
    "laam_shamsiyah", "ham_wasl", "slnt", "qalaqah",
    "waqf_lazim", "waqf_awla",
]
CAP = 15.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("spans_jsonl")
    ap.add_argument("--out", required=True)
    ap.add_argument("--cap", type=float, default=CAP)
    args = ap.parse_args()

    n_classes = len(RULE_CLASSES)
    pos_frames = [0] * n_classes
    total_frames = 0

    for line in open(args.spans_jsonl, encoding="utf-8"):
        r = json.loads(line)
        total_frames += r["n_frames"]
        for cid, s, e in r["spans"]:
            pos_frames[cid] += (e - s + 1)

    print(f"{'classe':<22} {'frames+':>10} {'frac':>7} {'pos_weight':>11}")
    weights = {}
    for cid, name in enumerate(RULE_CLASSES):
        pos = pos_frames[cid]
        neg = max(total_frames - pos, 1)
        w = min(args.cap, (neg / max(pos, 1)) ** 0.5) if pos > 0 else args.cap
        weights[name] = round(w, 3)
        frac = 100 * pos / max(total_frames, 1)
        print(f"{name:<22} {pos:>10} {frac:>6.3f}% {w:>11.3f}")

    Path(args.out).write_text(json.dumps(weights, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\nEcrit -> {args.out}")


if __name__ == "__main__":
    main()
