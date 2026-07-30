#!/usr/bin/env python3
"""DEUX PASSES : localiser AVEC contexte, entendre SANS contexte.

L'IDEE (utilisateur, 2026-07-31). Le modele a deux regimes MESURES :

    sans contexte (mot seul)  -> fidele      93,9 % des fautes du corpus
                                             sont ecrites telles quelles
    avec contexte (phrase)    -> canonique   12 modeles sur 12 reecrivent

Plutot que de reentrainer pour supprimer le second regime, on se sert des deux :
la passe AVEC contexte sait ou est chaque mot (l'alignement force y est bon), la
passe SANS contexte sait ce qui a ete reellement prononce. On compare alors deux
TEXTES, pas deux scores.

CE QUE CE BANC N'EST PAS. Ce n'est pas le test de fenetre etroite deja refute
(`gop_fenetre_etroite_vs_large.py` : -0,68 contre +3,59, 0/4). Celui-la
recalculait `gop = forced - free` sur l'extrait court -- les deux termes
s'effondrent ensemble et l'ecart se referme. Ici on ne calcule aucun gop : on
DECODE LIBREMENT l'extrait et on lit le texte. C'est une autre quantite.

LES DEUX CHIFFRES SE LISENT ENSEMBLE. Detection sur le mot faute ET collateral
sur les mots corrects de la meme phrase. Une detection de 100 % obtenue en
signalant tout le monde ne vaut rien -- c'est la regle du projet, et c'est
l'erreur que l'app existe pour ne pas commettre.

Usage :
    PYTHONPATH=... /usr/bin/python3.14 banc_deux_passes.py \
        --dossier data/tts_concat_test [--marges 0.10,0.20,0.30]
"""
import argparse
import json
import os
import sys
import unicodedata
from pathlib import Path

os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import numpy as np
import onnxruntime as ort
import sentencepiece as spm

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from assainir_corpus_fautes import lire_wav  # noqa: E402
from gop_fenetre_etroite_vs_large import (ECH_PAR_FRAME, spans_de_mots,  # noqa: E402
                                          viterbi_force)
from mel_numpy_reference import compute_mel_features  # noqa: E402

HARAKAT = set("ًٌٍَُِّْٰ")


def sans_harakat(s):
    return "".join(c for c in unicodedata.normalize("NFC", s) if c not in HARAKAT)


def logprobs(sess, pcm):
    f = compute_mel_features(pcm).astype(np.float32)
    out = sess.run(None, {"audio_signal": f[None],
                          "length": np.array([f.shape[1]], dtype=np.int64)})
    return np.asarray(out[0][0], dtype=np.float32)


def decode(lp, pieces):
    best = lp.argmax(axis=1)
    blank = lp.shape[1] - 1
    s, prec = [], -1
    for k in best:
        if k != blank and k != prec:
            s.append(pieces[k])
        prec = k
    return "".join(s).replace("▁", " ").strip()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--dossier", default=str(BASE / "data" / "tts_concat_test"))
    p.add_argument("--modele", default="/tmp/claude-1000/modele")
    p.add_argument("--tokenizer",
                   default=str(BASE / "tokenizers" / "tajweed_bpe_v1" / "tokenizer.model"))
    p.add_argument("--marges", default="0.10,0.20,0.30")
    args = p.parse_args()

    d = Path(args.dossier)
    pieces = json.load(open(Path(args.modele) / "vocab.json", encoding="utf-8"))
    sp = spm.SentencePieceProcessor(model_file=args.tokenizer)
    sess = ort.InferenceSession(str(Path(args.modele) / "model.onnx"),
                                providers=["CPUExecutionProvider"])
    lignes = [json.loads(l) for l in open(d / "manifest.jsonl", encoding="utf-8")]
    print(f"{len(lignes)} phrases a faute VERIFIEE, modele {args.modele}\n")

    # Temoin : que fait la passe AVEC contexte, seule ? C'est l'app actuelle.
    reecrits = 0
    for r in lignes:
        lp = logprobs(sess, lire_wav(d / "wav" / r["clip_faute"]))
        libre = decode(lp, pieces).split()
        att = r["correct_text"].split()
        i = r["mot_index"]
        if i < len(libre) and sans_harakat(libre[i]) == sans_harakat(att[i]):
            reecrits += 1
    print(f"PASSE AVEC CONTEXTE SEULE (l'app aujourd'hui) : le mot faute est "
          f"reecrit CANONIQUE dans {reecrits}/{len(lignes)} phrases "
          f"({100*reecrits/len(lignes):.0f} %)\n")

    # La regle « entendu != attendu » signale 97-99 % des mots CORRECTS : un
    # extrait de 0,4 s decode seul ne retombe presque jamais exactement sur le
    # mot attendu. La vraie question n'est donc pas binaire mais de
    # SEPARABILITE -- l'ecart entendu/attendu est-il plus grand sur un mot
    # faute que sur un mot correct ? Si les deux distributions se recouvrent,
    # aucun seuil ne sauvera l'idee, et le dire coute une minute.
    def cer(a, b):
        if not b:
            return 1.0
        d = [[0] * (len(b) + 1) for _ in range(len(a) + 1)]
        for i in range(len(a) + 1):
            d[i][0] = i
        for j in range(len(b) + 1):
            d[0][j] = j
        for i in range(1, len(a) + 1):
            for j in range(1, len(b) + 1):
                d[i][j] = min(d[i-1][j] + 1, d[i][j-1] + 1,
                              d[i-1][j-1] + (a[i-1] != b[j-1]))
        return d[-1][-1] / len(b)

    print(f"{'marge':>7} {'detection':>10} {'collateral':>11} {'det. lettres':>13} "
          f"{'det. harakat':>13}")
    print("-" * 60)
    for marge_s in [float(x) for x in args.marges.split(",")]:
        marge = int(marge_s * 16000)
        det, tot, coll, coll_tot = 0, 0, 0, 0
        det_k = {"letter": [0, 0], "harakat": [0, 0]}
        for r in lignes:
            att = r["correct_text"].split()
            i = r["mot_index"]
            for etat, clip in (("faute", r["clip_faute"]), ("correct", r["clip_correct"])):
                pcm = lire_wav(d / "wav" / clip)
                lp = logprobs(sess, pcm)
                ids = sp.encode(r["correct_text"])
                v = viterbi_force(lp, ids)
                if v is None:
                    continue
                _, tokf = v
                mots, _, spans = spans_de_mots(r["correct_text"], sp, tokf, lp.shape[0])
                for k, sp_k in enumerate(spans):
                    if sp_k is None:
                        continue
                    a = max(0, sp_k[0] * ECH_PAR_FRAME - marge)
                    b = min(len(pcm), sp_k[1] * ECH_PAR_FRAME + marge)
                    if b - a < 3200:
                        continue
                    entendu = decode(logprobs(sess, pcm[a:b]), pieces)
                    signale = sans_harakat(entendu.replace(" ", "")) != \
                        sans_harakat(mots[k]) if r["kind"] == "letter" \
                        else entendu.replace(" ", "") != mots[k]
                    if etat == "faute" and k == i:
                        tot += 1
                        det += signale
                        det_k[r["kind"]][1] += 1
                        det_k[r["kind"]][0] += signale
                    elif not (etat == "faute" and k == i):
                        coll_tot += 1
                        coll += signale
        print(f"{marge_s:>7.2f} {100*det/max(1,tot):>9.0f} % "
              f"{100*coll/max(1,coll_tot):>10.1f} % "
              f"{100*det_k['letter'][0]/max(1,det_k['letter'][1]):>12.0f} % "
              f"{100*det_k['harakat'][0]/max(1,det_k['harakat'][1]):>12.0f} %")
    print("-" * 60)
    print("\ncollateral = mots CORRECTS signales a tort (les autres mots de la "
          "phrase fautee + tous les mots de la phrase correcte).")

    # SEPARABILITE : distribution du CER(entendu, attendu) selon que le mot est
    # faute ou correct, a marge fixee. C'est ce qui decide si un seuil existe.
    marge = int(0.20 * 16000)
    cer_faute, cer_correct = [], []
    for r in lignes:
        i = r["mot_index"]
        for etat, clip in (("faute", r["clip_faute"]), ("correct", r["clip_correct"])):
            pcm = lire_wav(d / "wav" / clip)
            lp = logprobs(sess, pcm)
            v = viterbi_force(lp, sp.encode(r["correct_text"]))
            if v is None:
                continue
            _, tokf = v
            mots, _, spans = spans_de_mots(r["correct_text"], sp, tokf, lp.shape[0])
            for k, sk in enumerate(spans):
                if sk is None:
                    continue
                a = max(0, sk[0] * ECH_PAR_FRAME - marge)
                b = min(len(pcm), sk[1] * ECH_PAR_FRAME + marge)
                if b - a < 3200:
                    continue
                e = decode(logprobs(sess, pcm[a:b]), pieces).replace(" ", "")
                c = cer(sans_harakat(e), sans_harakat(mots[k]))
                (cer_faute if (etat == "faute" and k == i) else cer_correct).append(c)
    import statistics as st
    print(f"\nSEPARABILITE a marge 0,20 s -- CER(entendu sans contexte, attendu) :")
    print(f"  mots FAUTES   n={len(cer_faute):<4} median {st.median(cer_faute):.3f}  "
          f"q1 {np.quantile(cer_faute,0.25):.3f}  q3 {np.quantile(cer_faute,0.75):.3f}")
    print(f"  mots CORRECTS n={len(cer_correct):<4} median {st.median(cer_correct):.3f}  "
          f"q1 {np.quantile(cer_correct,0.25):.3f}  q3 {np.quantile(cer_correct,0.75):.3f}")
    print(f"\n  meilleur compromis atteignable (balayage du seuil) :")
    print(f"  {'seuil':>7} {'detection':>10} {'collateral':>11}")
    for s_ in [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7]:
        det = sum(1 for c in cer_faute if c > s_) / max(1, len(cer_faute))
        col = sum(1 for c in cer_correct if c > s_) / max(1, len(cer_correct))
        print(f"  {s_:>7.1f} {100*det:>9.0f} % {100*col:>10.1f} %")


if __name__ == "__main__":
    main()
