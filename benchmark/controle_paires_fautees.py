#!/usr/bin/env python3
"""CONTROLE OBLIGATOIRE : la faute synthetisee S'ENTEND-ELLE vraiment ?

C'est ce controle qui a tue le montage audio (`mort_montage_audio_splice`) en
cinq minutes : l'outil remplacait une frame de 80 ms, le modele continuait de
lire la lettre D'ORIGINE, et l'entrainement aurait donc appris l'INVERSE de la
cible. Aucun corpus de fautes ne part a l'entrainement sans passer ici.

METHODE — la matrice 2x2 des scores d'alignement force. Pour chaque paire on
calcule le log-vraisemblance CTC des DEUX textes sur les DEUX audios :

                        texte faute   texte correct
    audio faute              A              B          il faut A > B
    audio correct            C              D          il faut D > C

La faute est portee par le SON si et seulement si chaque audio prefere son
propre texte. Marge = (A-B) + (D-C), en log par mot du verset.

Pourquoi cette forme plutot qu'une comparaison de transcriptions : le modele a
un BIAIS CANONIQUE mesure (`piege_biais_canonique_contexte`) -- en fenetre large
il REECRIT la forme canonique meme quand il a entendu la faute. Un decodage
libre qui rend le texte correct ne prouve donc rien. L'alignement force, lui,
n'a rien a reecrire : on lui impose le texte et on lit ce que l'acoustique en
pense. Le decodage libre est quand meme affiche, comme temoin du biais.

Usage :
    PYTHONPATH=... /usr/bin/python3.14 controle_paires_fautees.py \
        [--dossier data/tts_phrases_fautees] [--modele /tmp/claude-1000/modele]
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

NEG = -1e30


def lire_wav(chemin):
    with wave.open(str(chemin)) as w:
        n_canaux, largeur, sr = w.getnchannels(), w.getsampwidth(), w.getframerate()
        brut = w.readframes(w.getnframes())
    if largeur != 2:
        raise ValueError(f"{chemin}: {largeur*8} bits, attendu 16")
    x = np.frombuffer(brut, dtype=np.int16).astype(np.float32) / 32768.0
    if n_canaux > 1:
        x = x.reshape(-1, n_canaux).mean(axis=1)
    if sr != 16000:  # XTTS sort du 24 kHz, le modele veut du 16 kHz
        n = int(round(len(x) * 16000 / sr))
        x = np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)
    return x.astype(np.float32)


def logprobs(sess, pcm):
    feats = compute_mel_features(pcm).astype(np.float32)
    out = sess.run(None, {"audio_signal": feats[None],
                          "length": np.array([feats.shape[1]], dtype=np.int64)})
    return np.asarray(out[0][0], dtype=np.float32)   # (T, V)


def decode_glouton(lp, pieces):
    best = lp.argmax(axis=1)
    blank = lp.shape[1] - 1
    sortie, prec = [], -1
    for k in best:
        if k != blank and k != prec:
            sortie.append(pieces[k])
        prec = k
    return "".join(sortie).replace("▁", " ").strip()


def score_force(lp, ids):
    """log P(ids | lp) par l'algorithme forward sur le treillis CTC etendu.

    Somme sur TOUS les alignements (et non le meilleur seul) : c'est la
    vraisemblance du texte, ce qui se compare d'un texte a l'autre.
    """
    T, V = lp.shape
    blank = V - 1
    etendu = [blank]
    for i in ids:
        etendu += [i, blank]
    S = len(etendu)
    if T < (S + 1) // 2:
        return NEG
    a = np.full(S, NEG, dtype=np.float64)
    a[0] = lp[0, etendu[0]]
    if S > 1:
        a[1] = lp[0, etendu[1]]
    for t in range(1, T):
        prec = a
        b = prec.copy()
        b[1:] = np.logaddexp(b[1:], prec[:-1])
        saut = np.full(S, NEG)
        ok = np.array([s >= 2 and etendu[s] != blank and etendu[s] != etendu[s - 2]
                       for s in range(S)])
        saut[2:] = np.where(ok[2:], prec[:-2], NEG)
        a = np.logaddexp(b, saut) + lp[t, etendu].astype(np.float64)
    return float(np.logaddexp(a[-1], a[-2])) if S > 1 else float(a[-1])


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--dossier", default=str(BASE / "data" / "tts_phrases_fautees"))
    p.add_argument("--modele", default="/tmp/claude-1000/modele")
    p.add_argument("--tokenizer", default=str(BASE / "tokenizers" / "tajweed_bpe_v1" / "tokenizer.model"))
    p.add_argument("--manifeste", default="manifest.jsonl")
    p.add_argument("--par-substitution", action="store_true",
                   help="rendement par couple de lettres / type de harakat")
    p.add_argument("--marge-min", type=float, default=0.0,
                   help="marge par mot en dessous de laquelle la paire est rejetee")
    args = p.parse_args()

    dossier = Path(args.dossier)
    pieces = json.load(open(Path(args.modele) / "vocab.json", encoding="utf-8"))
    sp = spm.SentencePieceProcessor(model_file=args.tokenizer)
    if sp.get_piece_size() != len(pieces):
        raise SystemExit(f"tokenizer {sp.get_piece_size()} pieces != vocab {len(pieces)} "
                         "-- ce n'est pas le tokenizer de ce modele")
    for k in range(0, len(pieces), max(1, len(pieces) // 50)):
        if sp.id_to_piece(k) != pieces[k]:
            raise SystemExit(f"piece {k} differe : {sp.id_to_piece(k)!r} vs {pieces[k]!r}")

    sess = ort.InferenceSession(str(Path(args.modele) / "model.onnx"),
                                providers=["CPUExecutionProvider"])
    noms = [i.name for i in sess.get_inputs()]
    if "audio_signal" not in noms:
        raise SystemExit(f"export inutilisable : entrees {noms} (cf. CLAUDE.md)")

    lignes = [json.loads(l) for l in open(dossier / args.manifeste, encoding="utf-8")]
    retenues, rejetees = [], []
    print(f"{len(lignes)} paires, modele {args.modele}\n")
    detaille = not args.par_substitution
    if detaille:
        print(f"{'#':>3} {'type':8} {'detail':16} {'A-B':>8} {'D-C':>8} {'marge/mot':>10}  verdict")
        print("-" * 78)

    for d in lignes:
        wf = lire_wav(dossier / "wav" / d["clip_faute"])
        wc = lire_wav(dossier / "wav" / d["clip_correct"])
        lpf, lpc = logprobs(sess, wf), logprobs(sess, wc)
        idf = sp.encode(d["text"])
        idc = sp.encode(d["correct_text"])
        A, B = score_force(lpf, idf), score_force(lpf, idc)
        C, D = score_force(lpc, idf), score_force(lpc, idc)
        nmots = max(1, len(d["correct_text"].split()))
        marge = ((A - B) + (D - C)) / nmots
        ok = A > B and D > C and marge >= args.marge_min
        d["_A"], d["_B"], d["_C"], d["_D"] = A, B, C, D
        d["_marge"] = marge
        d["_libre_faute"] = decode_glouton(lpf, pieces)
        d["_libre_correct"] = decode_glouton(lpc, pieces)
        (retenues if ok else rejetees).append(d)
        if detaille:
            print(f"{len(retenues)+len(rejetees)-1:>3} {d['kind']:8} {d['detail'][:16]:16} "
                  f"{A-B:>8.2f} {D-C:>8.2f} {marge:>10.3f}  "
                  f"{'RETENUE' if ok else 'REJETEE'}")
        elif (len(retenues)+len(rejetees)) % 50 == 0:
            print(f"  {len(retenues)+len(rejetees)}/{len(lignes)}...", flush=True)

    n = len(lignes)
    print("-" * 78)
    print(f"\n{len(retenues)}/{n} retenues ({100*len(retenues)/max(1,n):.0f} %), "
          f"{len(rejetees)} rejetees")
    for etiq, lot in (("lettre", "letter"), ("harakat", "harakat")):
        tot = [d for d in lignes if d["kind"] == lot]
        bon = [d for d in retenues if d["kind"] == lot]
        if tot:
            print(f"  {etiq:8} : {len(bon)}/{len(tot)} retenues, "
                  f"marge mediane {np.median([d['_marge'] for d in tot]):+.3f}")

    if args.par_substitution:
        import collections
        par = collections.defaultdict(lambda: [0, 0])
        for d in lignes:
            cle = d["detail"].split(":")[0] if d["kind"] == "harakat" else d["detail"]
            par[cle][1] += 1
            par[cle][0] += 1 if d in retenues else 0
        print("\nRENDEMENT PAR SUBSTITUTION (retenues / total) :")
        for cle, (bon, tot) in sorted(par.items(), key=lambda kv: -kv[1][0]/max(1,kv[1][1])):
            if tot >= 3:
                print(f"  {cle:14} {bon:>4}/{tot:<4} {100*bon/tot:>5.0f} %")

    print("\nTEMOIN DU BIAIS CANONIQUE (decodage libre de l'audio FAUTE) :")
    for d in lignes[:4]:
        canon = d["_libre_faute"].split() == d["correct_text"].split()
        print(f"  #{lignes.index(d)} demande  : {d['text']}")
        print(f"     entendu : {d['_libre_faute']}")
        print(f"     -> le modele {'REECRIT LE CANONIQUE' if canon else 'garde la faute'}")

    sortie = dossier / "manifest_controle.jsonl"
    with open(sortie, "w", encoding="utf-8") as g:
        for d in retenues:
            g.write(json.dumps(d, ensure_ascii=False) + "\n")
    print(f"\n{len(retenues)} paires validees -> {sortie}")
    if len(retenues) < 0.5 * n:
        print("\nMOINS DE LA MOITIE DES PAIRES PASSE : ne pas passer a l'echelle, "
              "le generateur ne rend pas la faute audible.")


if __name__ == "__main__":
    main()
