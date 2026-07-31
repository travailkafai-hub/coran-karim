#!/usr/bin/env python3
"""La fenetre +/- 1 mot survit-elle a de la recitation CONTINUE ?

CE QUI EST EN JEU. Sur des phrases ASSEMBLEES (mots synthetises separement puis
mis bout a bout), juger un mot dans une fenetre de +/- 1 mot double la detection
-- 53 % contre 25 % sur la phrase entiere, a collateral egal, sans reentrainer.
Mais ces phrases ont des frontieres de mots NETTES par construction. Sur de la
recitation continue il y a coarticulation, pas de frontiere franche, et la
fenetre risque de couper en plein son.

Si le collateral explose ici, les 53 % ne valent rien : ils seraient un artefact
du corpus de mesure. C'est le controle a passer AVANT d'en tirer quoi que ce
soit d'architectural.

PROTOCOLE : celui du projet (on fausse un mot ATTENDU sur N, sur le meme audio),
applique au flux BRUT du device -- vraie recitation continue, 296 mots. Le
protocole surestime la detection par rapport a une vraie faute acoustique, mais
ce n'est pas ce qu'on mesure ici : on compare DEUX FENETRES sur le meme audio et
les memes fautes. C'est la comparaison qui porte l'information.

Usage :
    PYTHONPATH=... /usr/bin/python3.14 banc_fenetre_mot_flux_reel.py
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
from banc_regles_gop import (fauter, logprobs_flux, spans_mots,  # noqa: E402
                             trois_gop)

ECH_PAR_FRAME = 1280


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--flux", default="/tmp/claude-1000/brut.wav")
    p.add_argument("--cible", default="/tmp/claude-1000/cible_v2.json")
    p.add_argument("--modele", default="/tmp/claude-1000/modele")
    p.add_argument("--tokenizer",
                   default=str(BASE / "tokenizers" / "tajweed_bpe_v1" / "tokenizer.model"))
    p.add_argument("--un-sur", type=int, default=5)
    p.add_argument("--graine", type=int, default=13)
    args = p.parse_args()

    sp = spm.SentencePieceProcessor(model_file=args.tokenizer)
    sess = ort.InferenceSession(str(Path(args.modele) / "model.onnx"),
                                providers=["CPUExecutionProvider"])
    mots = json.load(open(args.cible, encoding="utf-8"))
    pcm = lire_wav(args.flux)
    print(f"recitation continue : {len(pcm)/16000:.0f} s, {len(mots)} mots", flush=True)

    lp = logprobs_flux(sess, pcm)
    spans = spans_mots(sp, lp, mots)
    if spans is None:
        raise SystemExit("alignement global impossible")
    print(f"{sum(1 for s in spans if s)}/{len(mots)} mots alignes\n", flush=True)

    rng = np.random.default_rng(args.graine)
    fautes = {i for i in range(len(mots)) if i % args.un_sur == 0}
    res = {"bloc": ([], []), "fenetre": ([], [])}

    for i, m in enumerate(mots):
        if spans[i] is None:
            continue
        cible = m
        if i in fautes:
            f = fauter(m, rng)
            if f is None:
                continue
            cible = f

        g = trois_gop(sp, lp, spans[i], cible)
        if g is not None:
            res["bloc"][0 if i in fautes else 1].append(g[2])

        # Fenetre +/- 1 mot : bornes prises sur les voisins ALIGNES, puis
        # l'audio est RE-ENCODE. C'est bien une seconde passe du modele, pas une
        # relecture des memes logprobs -- toute la question est la.
        j0 = next((k for k in range(i - 1, -1, -1) if spans[k]), i)
        j1 = next((k for k in range(i + 1, len(mots)) if spans[k]), i)
        a = spans[j0][0] * ECH_PAR_FRAME
        b = min(len(pcm), spans[j1][1] * ECH_PAR_FRAME)
        if b - a < 3200:
            continue
        locaux = [mots[k] if k != i else cible for k in (j0, i, j1)]
        locaux = [x for k, x in zip((j0, i, j1), locaux)
                  if k == i or k != i]        # garde l'ordre j0, i, j1
        lpw = logprobs_flux(sess, pcm[a:b])
        sw = spans_mots(sp, lpw, locaux)
        if sw is None:
            continue
        gi = 1 if j0 != i else 0
        gw = trois_gop(sp, lpw, sw[gi], cible)
        if gw is not None:
            res["fenetre"][0 if i in fautes else 1].append(gw[2])

    print(f"{'fenetre de jugement':>22} {'faute med':>10} {'correct med':>12} "
          f"{'ECART':>7} {'detection a 2%':>15}")
    print("-" * 72)
    for cle, nom in (("bloc", "bloc entier (app)"), ("fenetre", "+/- 1 mot (2e passe)")):
        fa = np.array([x for x in res[cle][0] if x == x])
        co = np.array([x for x in res[cle][1] if x == x])
        if not len(fa) or not len(co):
            continue
        s = np.quantile(co, 0.02)
        print(f"{nom:>22} {np.median(fa):>10.3f} {np.median(co):>12.3f} "
              f"{np.median(co)-np.median(fa):>7.3f} "
              f"{100*float((fa < s).mean()):>14.0f} %")
    print("-" * 72)
    print(f"\n{len(res['bloc'][0])} mots fautes, {len(res['bloc'][1])} corrects")
    print("Si la fenetre ne gagne rien ICI alors qu'elle doublait la detection "
          "sur phrases assemblees, le gain venait des frontieres de mots nettes "
          "du corpus de mesure -- pas d'une propriete du modele.")


if __name__ == "__main__":
    main()
