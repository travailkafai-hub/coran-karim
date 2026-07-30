#!/usr/bin/env python3
"""Ou faut-il couper pour isoler UN mot ? Calibration, avant toute conclusion.

POURQUOI CE SCRIPT EXISTE. Le banc deux passes a rendu un CER median de 1,000
sur les mots CORRECTS -- l'extrait decode ne retombait jamais sur le mot
attendu, meme sans faute. Conclure « les deux passes ne marchent pas » aurait
ete conclure sur un banc casse. Deux causes connues, toutes deux documentees
dans le projet :

  1. L'ALIGNEMENT CTC EST PEAKY. Il marque la frame ou le token culmine, pas
     l'etendue acoustique du mot. C'est exactement ce qui a tue le montage audio
     (`mort_montage_audio_splice`) : une frame de 80 ms au lieu du phoneme.
  2. LE MODELE DEPLOYE EST CAUSAL avec 13 frames de lookahead (att_context
     [70,13], cf. Horloge.kt : LOOKAHEAD_FRAMES = 13, ECH_PAR_FRAME = 1280).
     L'emission est donc RETARDEE par rapport au son : la frame f ne parle pas
     de l'audio a f x 1280, mais d'avant.

On balaye donc deux choses a la fois, sur de l'audio dont on SAIT qu'il est
correct : le decalage a appliquer, et la politique d'etendue.

    pic       : les seules frames alignees sur le mot (ce que faisait le banc)
    mi-chemin : du milieu du mot precedent au milieu du suivant

Le critere est simple et non circulaire : sur un mot CORRECT, le decodage libre
de l'extrait doit rendre ce mot. Tant que ce n'est pas le cas, l'extrait n'est
pas le mot, et aucune mesure de detection faite dessus ne veut rien dire.

Usage :
    PYTHONPATH=... /usr/bin/python3.14 calibrer_decoupe_mot.py \
        [--dossier data/tts_concat_test] [--n 40]
"""
import argparse
import json
import os
import sys
from pathlib import Path

os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import numpy as np
import onnxruntime as ort
import sentencepiece as spm

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from assainir_corpus_fautes import lire_wav  # noqa: E402
from banc_deux_passes import decode, logprobs, sans_harakat  # noqa: E402
from gop_fenetre_etroite_vs_large import spans_de_mots, viterbi_force  # noqa: E402

ECH_PAR_FRAME = 1280


def cer(a, b):
    if not b:
        return 1.0
    d = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        prec, d[0] = d[0], i
        for j, cb in enumerate(b, 1):
            prec, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, prec + (ca != cb))
    return d[-1] / len(b)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--dossier", default=str(BASE / "data" / "tts_concat_test"))
    p.add_argument("--modele", default="/tmp/claude-1000/modele")
    p.add_argument("--tokenizer",
                   default=str(BASE / "tokenizers" / "tajweed_bpe_v1" / "tokenizer.model"))
    p.add_argument("--n", type=int, default=40)
    p.add_argument("--decalages", default="0,-4,-8,-13,-18")
    p.add_argument("--marge-s", type=float, default=0.20)
    args = p.parse_args()

    d = Path(args.dossier)
    pieces = json.load(open(Path(args.modele) / "vocab.json", encoding="utf-8"))
    sp = spm.SentencePieceProcessor(model_file=args.tokenizer)
    sess = ort.InferenceSession(str(Path(args.modele) / "model.onnx"),
                                providers=["CPUExecutionProvider"])
    lignes = [json.loads(l) for l in open(d / "manifest.jsonl", encoding="utf-8")][:args.n]
    marge = int(args.marge_s * 16000)

    # On precalcule alignement et spans sur l'audio CORRECT de chaque phrase.
    cas = []
    for r in lignes:
        pcm = lire_wav(d / "wav" / r["clip_correct"])
        lp = logprobs(sess, pcm)
        v = viterbi_force(lp, sp.encode(r["correct_text"]))
        if v is None:
            continue
        _, tokf = v
        mots, _, spans = spans_de_mots(r["correct_text"], sp, tokf, lp.shape[0])
        cas.append((pcm, mots, spans))
    print(f"{len(cas)} phrases CORRECTES, {sum(len(c[1]) for c in cas)} mots\n")
    print("critere : le decodage libre de l'extrait doit rendre le mot attendu "
          "(CER bas)\n")
    print(f"{'politique':>10} {'decalage':>9} {'CER median':>11} "
          f"{'CER moyen':>10} {'mots exacts':>12}")
    print("-" * 56)

    for politique in ("pic", "mi-chemin"):
        for dec in [int(x) for x in args.decalages.split(",")]:
            cers, exacts, n = [], 0, 0
            for pcm, mots, spans in cas:
                for k, sk in enumerate(spans):
                    if sk is None:
                        continue
                    if politique == "pic":
                        f0, f1 = sk
                    else:
                        prec = next((spans[j] for j in range(k - 1, -1, -1)
                                     if spans[j]), None)
                        suiv = next((spans[j] for j in range(k + 1, len(spans))
                                     if spans[j]), None)
                        f0 = (prec[1] + sk[0]) // 2 if prec else sk[0]
                        f1 = (sk[1] + suiv[0]) // 2 if suiv else sk[1]
                    a = max(0, (f0 + dec) * ECH_PAR_FRAME - marge)
                    b = min(len(pcm), (f1 + dec) * ECH_PAR_FRAME + marge)
                    if b - a < 3200:
                        continue
                    e = decode(logprobs(sess, pcm[a:b]), pieces).replace(" ", "")
                    c = cer(sans_harakat(e), sans_harakat(mots[k]))
                    cers.append(c)
                    exacts += c == 0.0
                    n += 1
            if n:
                print(f"{politique:>10} {dec:>9} {np.median(cers):>11.3f} "
                      f"{np.mean(cers):>10.3f} {100*exacts/n:>11.0f} %")
    print("-" * 56)
    print("\nSi aucune ligne ne descend nettement, l'extrait n'est pas le mot : "
          "la question des deux passes reste ouverte, mais le banc ne peut pas "
          "y repondre en l'etat.")


if __name__ == "__main__":
    main()
