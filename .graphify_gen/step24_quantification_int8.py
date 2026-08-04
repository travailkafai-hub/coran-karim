#!/usr/bin/env python3
"""Quantification INT8 du modele a trois tetes : mesuree, perdante, classee morte."""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mort_quantification_int8_dynamique_du_modele_trois_tetes",
     "[MORT] Quantification INT8 dynamique : 3x plus LENTE et l'argmax change sur 2,8 % des frames",
     "Question de l'utilisateur (2026-08-04) : « on n'a pas teste quantize le "
     "modele, voir comment il se comporte ». Jamais fait sur FastConformer -- "
     "les seuls int8 du projet etaient deux exports Whisper, piste abandonnee. "
     "Motivation legitime : le modele fait 459 Mo et une lenteur avait ete "
     "signalee sur device. "
     "MESURE (quantifier_trois_tetes.py, 20 s de recitation reelle, mediane "
     "sur 5 passes, CPU du poste) : "
     "taille 459 Mo -> 132 Mo (29 %) ; inference 82,7 ms -> 249,2 ms, soit une "
     "acceleration de x0,33 -- TROIS FOIS PLUS LENT. "
     "PRECISION, et c'est ce qui disqualifie : `logprobs` ecart moyen 1,14 et "
     "argmax CHANGE sur 2,79 % des frames ; `tajwid_logprobs` ecart moyen 0,31 "
     "et argmax change sur 17,13 %. Un argmax qui change est un TEXTE DECODE "
     "different, donc des verdicts differents -- le modele ne juge plus la "
     "meme chose. "
     "POURQUOI C'EST PLUS LENT : onnxruntime n'a pas su quantifier des dizaines "
     "d'operations du conformer (Slice, Tile, convolutions depthwise -- une "
     "quarantaine d'avertissements « unsupported type to quantize »). Le graphe "
     "se retrouve truffe de conversions int8<->float32 qui coutent plus cher "
     "que le calcul economise. "
     "RESERVE HONNETE : la vitesse est mesuree sur CPU x86 ; les noyaux INT8 "
     "sont souvent mieux optimises sur ARM, donc ce chiffre-la pourrait ne pas "
     "se transporter sur le telephone. La DEGRADATION DE PRECISION, elle, est "
     "arithmetique : elle se transporte a l'identique, et c'est elle qui ferme "
     "la piste. "
     "A ROUVRIR SEULEMENT en quantification STATIQUE avec calibration sur du "
     "vrai audio de recitation -- elle ne souffre pas des memes conversions et "
     "abime moins les sorties. Rien ne dit qu'elle sauverait la vitesse."),
]

LIENS = [
    ("mort_quantification_int8_dynamique_du_modele_trois_tetes",
     "mesure_sur_le_telephone_3_tetes_coute_moins_de_1_pourcent", "complete",
     "le cout d'execution ne vient pas des tetes, et l'int8 ne le reduit pas"),
]


def sha(ref="HEAD"):
    try:
        return subprocess.run(["git", "rev-parse", ref], capture_output=True,
                              text=True, cwd=RACINE, timeout=5).stdout.strip()
    except Exception:
        return ""


def main():
    g = json.loads(GRAPHE.read_text(encoding="utf-8"))
    connus = {n["id"] for n in g["nodes"]}
    ajoutes = 0
    for nid, label, rationale in NOEUDS:
        if nid in connus:
            continue
        g["nodes"].append({
            "label": label, "file_type": "concept",
            "source_file": "SOLUTIONS_RECITATION_V2.md", "source_location": None,
            "source_url": None, "captured_at": "2026-08-04", "author": None,
            "contributor": None, "rationale": rationale, "_origin": "semantic",
            "id": nid, "community": 0, "norm_label": label.lower(),
        })
        ajoutes += 1
    connus = {n["id"] for n in g["nodes"]}
    aretes = 0
    for s, t, rel, pourquoi in LIENS:
        if s not in connus or t not in connus:
            print(f"  ! cible absente : {s} -> {t}")
            continue
        g["links"].append({"source": s, "target": t, "relation_type": rel,
                           "source_location": pourquoi, "rationale": pourquoi})
        aretes += 1
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step24.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
