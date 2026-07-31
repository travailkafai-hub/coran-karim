#!/usr/bin/env python3
"""A partir de combien de CONTEXTE le modele cesse-t-il d'entendre la faute ?

LA QUESTION (utilisateur, 2026-07-31) : « la validation groupee est peut-etre
aussi la cause que le modele ne detecte plus les erreurs -- il valide tant que
le reciteur sonne confirme. Est-ce que ca va marcher avec le prochain modele,
ou on reste sur le meme probleme ? »

CE QUI REND LA REPONSE NON EVIDENTE. Le modele deploye est CAUSAL avec 70
frames de contexte gauche (5,6 s) et 13 a droite (1,04 s). Chaque frame de
sortie ne voit donc JAMAIS plus de ~6,6 s, quelle que soit la longueur du bloc.
Si c'est exact, un bloc de 16,5 s (la mediane mesuree sur la session de
reference) n'apporte rien de plus qu'un bloc de 7 s, et raccourcir les blocs ne
peut rien changer -- le defaut serait entierement dans le modele. Mais c'est un
raisonnement sur l'architecture, pas une mesure.

PROTOCOLE. On part du clip du mot faute SEUL -- regime ou son audibilite a deja
ete verifiee -- et on lui ajoute ses vrais voisins par paliers : 0, 1, 2, 3
mots de chaque cote, puis la phrase entiere. Le meme montage est fait avec le
mot CORRECT, pour lire detection et collateral ensemble.

On lit gop_C = forced(mot attendu) - forced(meilleure confusion) : la regle qui
s'est montree la meilleure (collateral divise par 3,4 a detection egale).

CE QUE CHAQUE FORME DE COURBE SIGNIFIE
  - l'ecart s'effondre des 1-2 voisins puis reste plat
        -> le prior s'installe tres tot ; raccourcir les blocs ne sauvera rien,
           seul un modele reentraine peut aider
  - l'ecart decroit progressivement jusqu'a la phrase entiere
        -> la longueur de bloc EST un levier, et le mode correcteur a interet a
           des blocs courts
  - l'ecart est deja faible sur le mot SEUL
        -> la faute ne s'entend pas dans ce montage, et c'est le corpus qu'il
           faut revoir, pas le modele

Usage :
    PYTHONPATH=... /usr/bin/python3.14 banc_contexte_et_detection.py [--n 250]
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

PALIERS = [0, 1, 2, 3, 99]        # 99 = phrase entiere
_etat = {}


def demarrer(modele, tokenizer):
    import onnxruntime as ort
    import sentencepiece as spm
    o = ort.SessionOptions()
    o.intra_op_num_threads = 1
    o.inter_op_num_threads = 1
    _etat["sess"] = ort.InferenceSession(modele, o, providers=["CPUExecutionProvider"])
    _etat["sp"] = spm.SentencePieceProcessor(model_file=tokenizer)


def traiter(r):
    """Rend {palier: (gop_faute, gop_correct, duree_s)} pour une paire."""
    from assainir_corpus_fautes import lire_wav
    from assembler_phrases_fautees import assembler
    from banc_regles_gop import logprobs_flux, spans_mots, trois_gop
    d = Path(r["_dossier"])
    ident = r["clip_faute"].replace("_faute.wav", "")
    mots = r["correct_text"].split()
    i = r["mot_index"]
    sp, sess = _etat["sp"], _etat["sess"]
    try:
        clips = [lire_wav(d / "mots" / f"{ident}_m{k:02d}.wav") for k in range(len(mots))]
        clip_faute = lire_wav(d / "mots" / f"{ident}_faute.wav")
    except Exception:
        return {}
    out = {}
    for p in PALIERS:
        a = max(0, i - p) if p != 99 else 0
        b = min(len(mots), i + p + 1) if p != 99 else len(mots)
        locaux = mots[a:b]
        j = i - a                                  # index du mot cible dans l'extrait
        res = []
        for remplace in (clip_faute, clips[i]):    # version fautee, puis correcte
            morceaux = clips[a:i] + [remplace] + clips[i + 1:b]
            audio = assembler(morceaux)
            try:
                lp = logprobs_flux(sess, audio)
                spans = spans_mots(sp, lp, locaux)
                g = trois_gop(sp, lp, spans[j], locaux[j]) if spans else None
            except Exception:
                g = None
            res.append(g[2] if g else float("nan"))
        out[p] = (res[0], res[1], len(audio) / 16000.0)
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--dossier", default=str(BASE / "data" / "tts_phrases_concat"))
    p.add_argument("--modele", default="/tmp/claude-1000/modele/model.onnx")
    p.add_argument("--tokenizer",
                   default=str(BASE / "tokenizers" / "tajweed_bpe_v1" / "tokenizer.model"))
    p.add_argument("--n", type=int, default=250)
    p.add_argument("--travailleurs", type=int, default=10)
    args = p.parse_args()

    d = Path(args.dossier)
    lignes = [json.loads(l) for l in open(d / "manifest.jsonl", encoding="utf-8")][:args.n]
    for r in lignes:
        r["_dossier"] = str(d)
    print(f"{len(lignes)} paires, contexte ajoute par paliers autour du mot faute\n",
          flush=True)

    t0 = time.time()
    acc = {p: ([], [], []) for p in PALIERS}
    with Pool(args.travailleurs, initializer=demarrer,
              initargs=(args.modele, args.tokenizer)) as pool:
        for k, res in enumerate(pool.imap_unordered(traiter, lignes, chunksize=4)):
            for p, (gf, gc, dur) in res.items():
                acc[p][0].append(gf)
                acc[p][1].append(gc)
                acc[p][2].append(dur)
            if (k + 1) % 50 == 0:
                print(f"  {k+1}/{len(lignes)}...", flush=True)

    print(f"\n({time.time()-t0:.0f} s)\n")
    print(f"{'contexte':>22} {'duree':>7} {'gop faute':>10} {'gop correct':>12} "
          f"{'ECART':>7} {'detection a 2%':>15}")
    print("-" * 78)
    for p in PALIERS:
        fa = np.array([x for x in acc[p][0] if x == x])
        co = np.array([x for x in acc[p][1] if x == x])
        if not len(fa) or not len(co):
            continue
        seuil = np.quantile(co, 0.02)
        nom = "phrase entiere" if p == 99 else (
            "mot SEUL" if p == 0 else f"+/- {p} mot{'s' if p > 1 else ''}")
        print(f"{nom:>22} {np.mean(acc[p][2]):>6.1f}s {np.median(fa):>10.3f} "
              f"{np.median(co):>12.3f} {np.median(co)-np.median(fa):>7.3f} "
              f"{100*float((fa < seuil).mean()):>14.0f} %")
    print("-" * 78)
    print("\nLe gop du mot faute qui MONTE avec le contexte = le modele se remet "
          "a preferer le canonique. C'est le biais, vu en fonction de la "
          "longueur du bloc.")


if __name__ == "__main__":
    main()
