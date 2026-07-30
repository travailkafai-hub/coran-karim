#!/usr/bin/env python3
"""Retire du corpus de fautes les clips dont l'audio dit le mot CORRECT.

MESURE QUI JUSTIFIE CE SCRIPT (2026-07-30, echantillon de 400 paires du lot
`tts_paired`) : seulement **70 %** des clips etiquetes « faute » portent
reellement la faute -- 83 % pour les lettres, 57 % pour les harakat. Extrapole
aux 18 195 fautes du corpus, cela fait environ **5 400 clips dont l'audio
prononce le mot correct alors que l'etiquette dit le contraire**.

POURQUOI LE QA D'ORIGINE NE POUVAIT PAS LE VOIR. `qa_tts_paired.py` compare la
transcription libre au texte demande et accepte jusqu'a `CER_REJECT = 0.5`. Un
mot dont UNE lettre change sur six a un CER de 0,17 : il passe, que le TTS ait
prononce la faute ou le mot canonique. Le critere ne pouvait pas distinguer les
deux cas -- il n'a jamais mesure l'audibilite. Sa branche `OK_BIAIS_CANONIQUE`
allait plus loin : quand l'ASR entendait le canonique, elle SUPPOSAIT le biais
de l'ASR et gardait le clip (77 cas seulement, donc l'effet reste borne).

LE CRITERE ICI. Sur l'audio du clip, on compare la vraisemblance CTC des deux
textes -- celui de l'etiquette et le canonique :

    garder  <=>  logP(texte etiquette | audio) > logP(texte canonique | audio)

L'alignement force n'a rien a reecrire, contrairement au decodage libre : c'est
ce qui le rend insensible au biais canonique du modele.

CE QUE CA NE PROUVE PAS. Le juge est le modele deploye ; un clip rejete l'est
« du point de vue de ce modele ». C'est le meme instrument qui servira a
l'entrainement, donc le critere est le bon pour ce qu'on en fait -- mais ce
n'est pas une verite acoustique absolue, et un clip rejete n'est pas efface :
il part dans un manifeste separe.

Usage :
    PYTHONPATH=... /usr/bin/python3.14 assainir_corpus_fautes.py \
        --dossier data/tts_augmentation [--travailleurs 8]
"""
import argparse
import json
import os
import sys
import time
import wave
from multiprocessing import Pool
from pathlib import Path

os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import numpy as np

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))

NEG = -1e30
_etat = {}


def demarrer(modele, tokenizer):
    import onnxruntime as ort
    import sentencepiece as spm
    from mel_numpy_reference import compute_mel_features
    o = ort.SessionOptions()
    o.intra_op_num_threads = 1
    o.inter_op_num_threads = 1
    _etat["sess"] = ort.InferenceSession(modele, o, providers=["CPUExecutionProvider"])
    _etat["sp"] = spm.SentencePieceProcessor(model_file=tokenizer)
    _etat["mel"] = compute_mel_features


def lire_wav(chemin):
    with wave.open(str(chemin)) as w:
        nc, sr = w.getnchannels(), w.getframerate()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
    x = x.astype(np.float32) / 32768.0
    if nc > 1:
        x = x.reshape(-1, nc).mean(axis=1)
    if sr != 16000:
        n = int(round(len(x) * 16000 / sr))
        x = np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)
    return x.astype(np.float32)


def score_force(lp, ids):
    T, V = lp.shape
    blank = V - 1
    ext = [blank]
    for i in ids:
        ext += [i, blank]
    S = len(ext)
    if T < (S + 1) // 2:
        return NEG
    a = np.full(S, NEG, dtype=np.float64)
    a[0] = lp[0, ext[0]]
    if S > 1:
        a[1] = lp[0, ext[1]]
    saut_ok = np.array([s >= 2 and ext[s] != blank and ext[s] != ext[s - 2]
                        for s in range(S)])
    col = np.asarray(ext)
    for t in range(1, T):
        b = a.copy()
        b[1:] = np.logaddexp(b[1:], a[:-1])
        saut = np.full(S, NEG)
        saut[2:] = np.where(saut_ok[2:], a[:-2], NEG)
        a = np.logaddexp(b, saut) + lp[t, col].astype(np.float64)
    return float(np.logaddexp(a[-1], a[-2])) if S > 1 else float(a[-1])


def juger(tache):
    chemin, texte, canonique = tache
    try:
        pcm = lire_wav(chemin)
        if len(pcm) < 3200:
            return ("COURT", None, None)
        f = _etat["mel"](pcm).astype(np.float32)
        out = _etat["sess"].run(None, {"audio_signal": f[None],
                                       "length": np.array([f.shape[1]], dtype=np.int64)})
        lp = np.asarray(out[0][0], dtype=np.float32)
        sp = _etat["sp"]
        a = score_force(lp, sp.encode(texte))
        b = score_force(lp, sp.encode(canonique))
        return ("OK" if a > b else "INAUDIBLE", a, b)
    except Exception as e:
        return (f"ERREUR:{str(e)[:40]}", None, None)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--dossier", default=str(BASE / "data" / "tts_augmentation"))
    p.add_argument("--manifeste", default="manifest.jsonl")
    p.add_argument("--modele", default="/tmp/claude-1000/modele/model.onnx")
    p.add_argument("--tokenizer",
                   default=str(BASE / "tokenizers" / "tajweed_bpe_v1" / "tokenizer.model"))
    p.add_argument("--travailleurs", type=int, default=8)
    p.add_argument("--champ-clip", default="clip")
    args = p.parse_args()

    d = Path(args.dossier)
    lignes = [json.loads(l) for l in open(d / args.manifeste, encoding="utf-8")]
    wav = d / "wav"
    taches = [(str(wav / r[args.champ_clip]), r["text"], r["correct_text"])
              for r in lignes]
    print(f"{len(taches)} clips a juger, {args.travailleurs} travailleurs", flush=True)

    t0 = time.time()
    res = []
    with Pool(args.travailleurs, initializer=demarrer,
              initargs=(args.modele, args.tokenizer)) as pool:
        for k, r in enumerate(pool.imap(juger, taches, chunksize=16)):
            res.append(r)
            if (k + 1) % 1000 == 0:
                dt = time.time() - t0
                print(f"  {k+1}/{len(taches)}  ({dt/(k+1)*1000:.0f} ms/clip, "
                      f"reste ~{(len(taches)-k-1)*dt/(k+1)/60:.0f} min)", flush=True)

    import collections
    stats = collections.Counter(r[0] for r in res)
    garde, rejet = [], []
    for r, (verdict, a, b) in zip(lignes, res):
        r["_verdict"] = verdict
        if a is not None:
            r["_marge"] = round(a - b, 3)
        (garde if verdict == "OK" else rejet).append(r)

    for nom, lot in (("audible", garde), ("inaudible", rejet)):
        chemin = d / f"manifest_{nom}.jsonl"
        with open(chemin, "w", encoding="utf-8") as g:
            for r in lot:
                g.write(json.dumps(r, ensure_ascii=False) + "\n")
        print(f"{len(lot):>6} -> {chemin}")

    n = len(lignes)
    print(f"\n{len(garde)}/{n} = {100*len(garde)/n:.1f} % de fautes AUDIBLES")
    print(f"  verdicts : {dict(stats)}")
    par = collections.defaultdict(lambda: [0, 0])
    for r in lignes:
        cle = r["detail"].split(":")[0] if r["kind"] == "harakat" else r["detail"]
        par[cle][1] += 1
        par[cle][0] += r["_verdict"] == "OK"
    print("\n  rendement par substitution (>= 20 cas) :")
    for c, (bon, tot) in sorted(par.items(), key=lambda kv: -kv[1][0] / max(1, kv[1][1])):
        if tot >= 20:
            print(f"    {c:14} {bon:>5}/{tot:<5} {100*bon/tot:>5.0f} %")


if __name__ == "__main__":
    main()
