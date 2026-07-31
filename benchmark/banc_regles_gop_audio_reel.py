#!/usr/bin/env python3
"""Les regles de gop sur de l'audio REELLEMENT faute. C'est le vrai test.

CE QUI CHANGE PAR RAPPORT A `banc_regles_gop.py`, et pourquoi ca compte.

Ce banc-la faussait le TEXTE ATTENDU sur un audio correct. C'est le protocole
historique du projet (il a mesure 100 % / 2,44 %) et il repond a une vraie
question -- « la chaine voit-elle un desaccord entre l'audio et la cible ? » --
mais l'audio y est toujours une recitation juste.

Ici, la cible reste CANONIQUE et c'est l'AUDIO qui porte la faute. C'est la
situation de l'application : quelqu'un recite mal, le texte attendu ne bouge
pas. Une regle peut tres bien reussir le premier test et echouer celui-ci : le
premier demande de detecter une cible impossible a caser dans le son, le second
demande d'entendre une difference acoustique fine.

Chaque paire fournit les deux etats avec la MEME voix et le MEME texte a un mot
pres, et l'audibilite de la faute a deja ete verifiee clip par clip
(`assembler_phrases_fautees.py`). Une faute non detectee ici est donc une faute
que la regle rate, pas une faute absente du son.

  detection  = le mot faute est-il signale sur l'audio FAUTE ?
  collateral = mots corrects signales a tort -- les autres mots de la phrase
               fautee, ET tous les mots de la phrase correcte.

Usage :
    PYTHONPATH=... /usr/bin/python3.14 banc_regles_gop_audio_reel.py \
        [--dossier data/tts_phrases_concat] [--n 300]
"""
import argparse
import json
import os
import sys
import time
from multiprocessing import Pool
from pathlib import Path

os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import numpy as np

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))

_etat = {}


def demarrer(modele, tokenizer):
    import onnxruntime as ort
    import sentencepiece as spm
    o = ort.SessionOptions()
    o.intra_op_num_threads = 1
    o.inter_op_num_threads = 1
    _etat["sess"] = ort.InferenceSession(modele, o, providers=["CPUExecutionProvider"])
    _etat["sp"] = spm.SentencePieceProcessor(model_file=tokenizer)


def traiter(tache):
    """Rend [(est_faute, (gopA, gopB, gopC)), ...] pour une paire."""
    from assainir_corpus_fautes import lire_wav
    from banc_regles_gop import logprobs_flux, spans_mots, trois_gop
    d, r = Path(tache["_dossier"]), tache
    sp, sess = _etat["sp"], _etat["sess"]
    sortie = []
    mots = r["correct_text"].split()          # la cible ATTENDUE ne bouge jamais
    for etat, clip in (("faute", r["clip_faute"]), ("correct", r["clip_correct"])):
        try:
            lp = logprobs_flux(sess, lire_wav(d / "wav" / clip))
        except Exception:
            continue
        spans = spans_mots(sp, lp, mots)
        if spans is None:
            continue
        # CONTROLE DE CONFUSION : l'alignement CTC est peaky, le span d'un mot
        # peut donc ne couvrir qu'une fraction de son etendue acoustique. Une
        # detection faible pourrait venir de la, et non du modele. On rejoue
        # donc chaque mot sur un span ELARGI (du milieu du mot precedent au
        # milieu du suivant) : si la detection remonte, le probleme est le
        # decoupage ; si elle ne bouge pas, c'est bien le modele qui n'entend
        # pas la faute en contexte.
        larges = []
        for k, sk in enumerate(spans):
            if sk is None:
                larges.append(None)
                continue
            prec = next((spans[j] for j in range(k - 1, -1, -1) if spans[j]), None)
            suiv = next((spans[j] for j in range(k + 1, len(spans)) if spans[j]), None)
            larges.append(((prec[1] + sk[0]) // 2 if prec else sk[0],
                           (sk[1] + suiv[0]) // 2 if suiv else sk[1]))
        for i, m in enumerate(mots):
            g = trois_gop(sp, lp, spans[i], m)
            gl = trois_gop(sp, lp, larges[i], m)
            if g is None:
                continue
            sortie.append((etat == "faute" and i == r["mot_index"],
                           g + ((gl[2] if gl else float("nan")),)))
    return sortie


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--dossier", default=str(BASE / "data" / "tts_phrases_concat"))
    p.add_argument("--modele", default="/tmp/claude-1000/modele/model.onnx")
    p.add_argument("--tokenizer",
                   default=str(BASE / "tokenizers" / "tajweed_bpe_v1" / "tokenizer.model"))
    p.add_argument("--n", type=int, default=300)
    p.add_argument("--travailleurs", type=int, default=10)
    args = p.parse_args()

    d = Path(args.dossier)
    lignes = [json.loads(l) for l in open(d / "manifest.jsonl", encoding="utf-8")]
    lignes = lignes[:args.n]
    for r in lignes:
        r["_dossier"] = str(d)
    print(f"{len(lignes)} paires a faute AUDIBLE verifiee, audio reellement faute",
          flush=True)

    t0 = time.time()
    res = {"A": ([], []), "B": ([], []), "C": ([], []), "D": ([], [])}
    with Pool(args.travailleurs, initializer=demarrer,
              initargs=(args.modele, args.tokenizer)) as pool:
        for k, lot in enumerate(pool.imap_unordered(traiter, lignes, chunksize=4)):
            for est_faute, g in lot:
                for cle, val in zip("ABCD", g):
                    res[cle][0 if est_faute else 1].append(val)
            if (k + 1) % 50 == 0:
                print(f"  {k+1}/{len(lignes)}...", flush=True)

    n_f, n_c = len(res["A"][0]), len(res["A"][1])
    print(f"\n{n_f} mots FAUTES, {n_c} mots corrects ({time.time()-t0:.0f} s)\n")
    libelle = {"A": "forced(Viterbi) - free   [app]",
               "B": "forced(forward) - free   [piste 0]",
               "C": "forced(att) - forced(alt) [piste 1]",
               "D": "regle C sur span ELARGI  [controle]"}
    print(f"{'regle':>6} {'':38} {'faute med':>10} {'correct med':>12} {'ECART':>8}")
    print("-" * 80)
    for k in "ABCD":
        fa = [x for x in res[k][0] if x == x]
        co = [x for x in res[k][1] if x == x]
        if not fa or not co:
            continue
        print(f"{k:>6} {libelle[k]:38} {np.median(fa):>10.3f} "
              f"{np.median(co):>12.3f} {np.median(co)-np.median(fa):>8.3f}")
    print("-" * 80)

    print("\nA COLLATERAL EGAL (2 %), quelle regle detecte le plus ?")
    print(f"{'regle':>6} {'seuil':>9} {'detection':>10}")
    for k in "ABCD":
        fa = np.array([x for x in res[k][0] if x == x])
        co = np.array([x for x in res[k][1] if x == x])
        if not len(fa) or not len(co):
            continue
        s = np.quantile(co, 0.02)          # seuil qui signale 2 % des corrects
        print(f"{k:>6} {s:>9.3f} {100*float((fa < s).mean()):>9.0f} %")

    print("\nET a detection egale, quel collateral ?")
    print(f"{'regle':>6} {'detection':>10} {'collateral':>11}")
    for cible in (0.80, 0.90):
        print(f"  -- cible {100*cible:.0f} % de detection --")
        for k in "ABCD":
            fa = np.array([x for x in res[k][0] if x == x])
            co = np.array([x for x in res[k][1] if x == x])
            if not len(fa) or not len(co):
                continue
            s = np.quantile(fa, cible)
            print(f"{k:>6} {100*float((fa < s).mean()):>9.0f} % "
                  f"{100*float((co < s).mean()):>10.1f} %")


if __name__ == "__main__":
    main()
