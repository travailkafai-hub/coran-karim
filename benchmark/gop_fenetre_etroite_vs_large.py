#!/usr/bin/env python3
"""Le GOP d'un mot depend-il de la LARGEUR de fenetre sur laquelle on le calcule ?

CE QUE CE BANC TESTE, ET POURQUOI.

L'app juge un mot par `gop = forced - free`. `forced` colle la cible sur
l'audio ; `free` est ce que le modele entend librement. Or il est MESURE
(`piege_biais_canonique_contexte`, 12 modeles sur 12) qu'en fenetre large le
modele REECRIT la forme canonique. Si `free` reecrit la cible, alors
`free ~ forced`, donc `gop ~ 0`, et **une vraie faute passe au VERT**. C'est
exactement ce que l'utilisateur a constate en s'en servant : « j'ai fait des
fautes deliberees, il les colorie, alors que le texte entendu en bas montre
bien que j'ai mal dit le mot ».

L'hypothese testee ici est architecturale, pas palliative : on ne deplace aucun
seuil, on remet le modele dans le regime ou il est MESURE fidele -- la fenetre
etroite. Le mot est localise par la fenetre large (elle est bonne pour ca), mais
JUGE sur une fenetre etroite recentree sur lui.

    gop_large   = forced - free, sur les frames du mot dans le bloc entier
    gop_etroit  = forced - free, sur un extrait audio recalcule autour du mot

Protocole : chaque paire fournit le MEME mot dans les deux etats (audio fautif
et audio correct, meme voix). Le pouvoir de detection est l'ECART entre les
deux ; un gop bas sur les deux ne detecte rien, il condamne tout le monde.

Usage :
    PYTHONPATH=... /usr/bin/python3.14 gop_fenetre_etroite_vs_large.py \
        [--dossier data/tts_phrases_fautees] [--marge-s 0.30]
"""
import argparse
import json
import os
import sys
import wave
from pathlib import Path

os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import numpy as np
import onnxruntime as ort
import sentencepiece as spm

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from mel_numpy_reference import compute_mel_features  # noqa: E402

ECH_PAR_FRAME = 1280        # 80 ms : sous-echantillonnage 8 x hop 10 ms
NEG = -1e30


def lire_wav(chemin):
    with wave.open(str(chemin)) as w:
        nc, lw, sr = w.getnchannels(), w.getsampwidth(), w.getframerate()
        brut = w.readframes(w.getnframes())
    x = np.frombuffer(brut, dtype=np.int16).astype(np.float32) / 32768.0
    if nc > 1:
        x = x.reshape(-1, nc).mean(axis=1)
    if sr != 16000:
        n = int(round(len(x) * 16000 / sr))
        x = np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)
    return x.astype(np.float32)


def logprobs(sess, pcm):
    f = compute_mel_features(pcm).astype(np.float32)
    out = sess.run(None, {"audio_signal": f[None],
                          "length": np.array([f.shape[1]], dtype=np.int64)})
    return np.asarray(out[0][0], dtype=np.float32)


def viterbi_force(lp, ids):
    """Meilleur chemin CTC contraint par `ids`. Rend l'etiquette par frame et
    l'indice de token par frame (-1 pour un blanc)."""
    T, V = lp.shape
    blank = V - 1
    ext, src = [blank], [-1]
    for k, i in enumerate(ids):
        ext += [i, blank]
        src += [k, -1]
    S = len(ext)
    if T < (S + 1) // 2:
        return None
    d = np.full((T, S), NEG, dtype=np.float64)
    bp = np.zeros((T, S), dtype=np.int8)
    d[0, 0] = lp[0, ext[0]]
    if S > 1:
        d[0, 1] = lp[0, ext[1]]
    for t in range(1, T):
        rest = d[t - 1]
        cand = np.stack([
            rest,
            np.concatenate(([NEG], rest[:-1])),
            np.concatenate(([NEG, NEG], np.where(
                [s >= 2 and ext[s] != blank and ext[s] != ext[s - 2]
                 for s in range(2, S)], rest[:-2], NEG))),
        ])
        arg = cand.argmax(axis=0)
        d[t] = cand.max(axis=0) + lp[t, ext].astype(np.float64)
        bp[t] = arg
    s = S - 1 if S == 1 or d[T - 1, S - 1] >= d[T - 1, S - 2] else S - 2
    tok = np.full(T, -1, dtype=np.int64)
    lab = np.zeros(T, dtype=np.int64)
    for t in range(T - 1, -1, -1):
        lab[t] = ext[s]
        tok[t] = src[s]
        s -= int(bp[t, s])
    return lab, tok


def spans_de_mots(texte, sp, tok, T):
    """Frames couvertes par chaque mot, d'apres l'alignement force."""
    ids, bornes, mots = [], [], texte.split()
    for m in mots:
        d = len(ids)
        ids += sp.encode(m)
        bornes.append((d, len(ids)))
    spans = []
    for (a, b) in bornes:
        f = np.where((tok >= a) & (tok < b))[0]
        spans.append((int(f[0]), int(f[-1]) + 1) if len(f) else None)
    return mots, ids, spans


def gop_sur(lp, ids_mot):
    """gop moyen par frame d'un mot juge sur CE tableau de logprobs."""
    r = viterbi_force(lp, ids_mot)
    if r is None:
        return None
    lab, _ = r
    forced = lp[np.arange(len(lab)), lab].astype(np.float64)
    free = lp.max(axis=1).astype(np.float64)
    return float((forced - free).mean())


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--dossier", default=str(BASE / "data" / "tts_phrases_fautees"))
    p.add_argument("--modele", default="/tmp/claude-1000/modele")
    p.add_argument("--tokenizer",
                   default=str(BASE / "tokenizers" / "tajweed_bpe_v1" / "tokenizer.model"))
    p.add_argument("--marge-s", type=float, default=0.30,
                   help="audio garde de part et d'autre du mot en fenetre etroite")
    p.add_argument("--manifeste", default="manifest_controle.jsonl")
    args = p.parse_args()

    dossier = Path(args.dossier)
    sp = spm.SentencePieceProcessor(model_file=args.tokenizer)
    sess = ort.InferenceSession(str(Path(args.modele) / "model.onnx"),
                                providers=["CPUExecutionProvider"])
    lignes = [json.loads(l) for l in open(dossier / args.manifeste, encoding="utf-8")]
    print(f"{len(lignes)} paires a faute AUDIBLE (deja filtrees par le controle)\n")
    print(f"{'#':>3} {'detail':14} {'mot attendu':16} "
          f"{'LARGE faute':>12} {'LARGE corr':>11} {'ecart':>7} | "
          f"{'ETROIT faute':>13} {'ETROIT corr':>12} {'ecart':>7}")
    print("-" * 108)

    marge = int(args.marge_s * 16000)
    ecarts_l, ecarts_e = [], []
    for num, d in enumerate(lignes):
        i = d["mot_index"]
        res = {}
        for etat, clip in (("faute", d["clip_faute"]), ("correct", d["clip_correct"])):
            pcm = lire_wav(dossier / "wav" / clip)
            lp = logprobs(sess, pcm)
            # On aligne le texte ATTENDU (le canonique), comme le fait l'app.
            ids = sp.encode(d["correct_text"])
            r = viterbi_force(lp, ids)
            if r is None:
                res[etat] = None
                continue
            _, tok = r
            mots, _, spans = spans_de_mots(d["correct_text"], sp, tok, lp.shape[0])
            if i >= len(spans) or spans[i] is None:
                res[etat] = None
                continue
            f0, f1 = spans[i]
            ids_mot = sp.encode(mots[i])
            g_large = gop_sur(lp[f0:f1], ids_mot)
            a = max(0, f0 * ECH_PAR_FRAME - marge)
            b = min(len(pcm), f1 * ECH_PAR_FRAME + marge)
            g_etroit = gop_sur(logprobs(sess, pcm[a:b]), ids_mot) if b - a > 3200 else None
            res[etat] = (g_large, g_etroit, mots[i])
        if not res.get("faute") or not res.get("correct"):
            print(f"{num:>3} {d['detail'][:14]:14} (alignement impossible)")
            continue
        (glf, gef, mot) = res["faute"]
        (glc, gec, _) = res["correct"]
        el = (glc - glf) if (glf is not None and glc is not None) else float("nan")
        ee = (gec - gef) if (gef is not None and gec is not None) else float("nan")
        ecarts_l.append(el)
        ecarts_e.append(ee)
        print(f"{num:>3} {d['detail'][:14]:14} {mot[:16]:16} "
              f"{glf:>12.3f} {glc:>11.3f} {el:>7.3f} | "
              f"{gef:>13.3f} {gec:>12.3f} {ee:>7.3f}")

    print("-" * 108)
    if ecarts_l:
        print(f"\necart median (correct - faute), c'est le POUVOIR DE DETECTION :")
        print(f"  fenetre LARGE  (ce que fait l'app) : {np.median(ecarts_l):+.3f}")
        print(f"  fenetre ETROITE (+/- {args.marge_s} s)    : {np.median(ecarts_e):+.3f}")
        mieux = sum(1 for a, b in zip(ecarts_l, ecarts_e) if b > a)
        print(f"  l'etroite separe mieux sur {mieux}/{len(ecarts_l)} paires")


if __name__ == "__main__":
    main()
