#!/usr/bin/env python3
"""Trois facons de calculer le gop, comparees sur le MEME audio et les MEMES spans.

LA QUESTION (utilisateur, 2026-07-31) : « malgre que le modele est confiant et
que `free` est correct, `forced` deconne, ce qui rend le jugement pas tout a
fait raisonnable ».

Le diagnostic tient en une phrase : la loss CTC optimise `log P(texte correct |
audio)`, c'est-a-dire la vraisemblance FORCEE -- mais uniquement sur le texte
CORRECT. Rien n'optimise la MARGE contre un texte faux. Or le gop EST une marge.
On juge sur une difference que rien n'a jamais entrainee.

LES TROIS REGLES COMPAREES

  A  gop = forced(Viterbi) - free      ce que fait l'app aujourd'hui
  B  gop = forced(forward) - free      piste 0 : somme sur TOUS les alignements
                                       au lieu du meilleur seul. CTC est peaky
                                       (une frame par token, blanc ailleurs) ;
                                       le meilleur chemin est donc domine par
                                       une poignee de frames et UNE mauvaise
                                       frame effondre le mot. La somme est bien
                                       moins sensible a cela.
  C  gop = forced(attendu) - forced(meilleure alternative plausible)
                                       piste 1 : on ne compare plus a `free`
                                       (un max sur TOUT, borne tres lache) mais
                                       a la meilleure confusion REELLE du mot.
                                       Les deux chemins traversent alors les
                                       memes frames difficiles, ce qui annule
                                       l'essentiel de la peakiness ET
                                       l'asymetrie de longueur.

C n'est pas une intuition : c'est la forme qui a marche le 2026-07-31 pour le
controle d'audibilite (93,9 % de bonnes decisions sur 18 195 clips, marge
mediane +3,6). Elle repond a « l'audio prefere-t-il ر ou ز ? » plutot qu'a
« le modele est-il sur de ce qu'il entend ? ».

PROTOCOLE, identique a celui qui a mesure 100 % / 2,44 % sur ce banc : on fausse
un mot ATTENDU sur N, sur le MEME audio, et on lit ensemble la detection et le
collateral. Les spans sont calcules UNE fois sur la cible vraie et gardes
identiques pour les trois regles : seule la regle de score varie.

Usage :
    PYTHONPATH=... /usr/bin/python3.14 banc_regles_gop.py [--un-sur 5]
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
from assainir_corpus_fautes import lire_wav, score_force  # noqa: E402
from confusions_recitation import variantes as alternatives  # noqa: E402
from gop_fenetre_etroite_vs_large import viterbi_force  # noqa: E402
from mel_numpy_reference import compute_mel_features  # noqa: E402

NEG = -1e30


def logprobs_flux(sess, pcm, bloc_s=60.0, recouvre_s=2.0):
    """Le flux entier ne passe pas en une fois : on decoupe, et on jette le
    recouvrement. Le modele est causal a contexte borne (70 frames a gauche,
    13 a droite), donc un recouvrement de 2 s suffit largement."""
    n_bloc, n_rec = int(bloc_s * 16000), int(recouvre_s * 16000)
    morceaux, debut = [], 0
    while debut < len(pcm):
        fin = min(len(pcm), debut + n_bloc)
        a = max(0, debut - n_rec)
        f = compute_mel_features(pcm[a:fin]).astype(np.float32)
        out = sess.run(None, {"audio_signal": f[None],
                              "length": np.array([f.shape[1]], dtype=np.int64)})
        lp = np.asarray(out[0][0], dtype=np.float32)
        jeter = 0 if a == debut else int(round((debut - a) / 1280))
        morceaux.append(lp[jeter:])
        debut = fin
    return np.concatenate(morceaux, axis=0)


def fauter(mot, rng):
    alt = alternatives(mot)
    return rng.choice(alt) if alt else None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--flux", default="/tmp/claude-1000/brut.wav")
    p.add_argument("--cible", default="/tmp/claude-1000/cible_v2.json")
    p.add_argument("--val-manifeste",
                   default=str(BASE / "nemo_manifests_dual" / "val_manifest.jsonl"),
                   help="versets JAMAIS vus a l'entrainement, plusieurs recitateurs")
    p.add_argument("--n-val", type=int, default=120,
                   help="0 pour ne mesurer que sur le flux device")
    p.add_argument("--modele", default="/tmp/claude-1000/modele")
    p.add_argument("--tokenizer",
                   default=str(BASE / "tokenizers" / "tajweed_bpe_v1" / "tokenizer.model"))
    p.add_argument("--un-sur", type=int, default=5, help="on fausse 1 mot sur N")
    p.add_argument("--graine", type=int, default=13)
    args = p.parse_args()

    sp = spm.SentencePieceProcessor(model_file=args.tokenizer)
    sess = ort.InferenceSession(str(Path(args.modele) / "model.onnx"),
                                providers=["CPUExecutionProvider"])
    # PLUSIEURS enregistrements, pas un seul. Le flux device donne les
    # conditions reelles de l'app ; les versets du manifeste de VALIDATION
    # donnent la diversite de recitateurs et un texte exact, sans le biais de
    # mesurer sur des donnees d'entrainement.
    items = []
    if Path(args.flux).exists():
        items.append(("device " + Path(args.flux).stem,
                      lire_wav(args.flux),
                      json.load(open(args.cible, encoding="utf-8"))))
    if args.n_val and Path(args.val_manifeste).exists():
        vus = 0
        for ligne in open(args.val_manifeste, encoding="utf-8"):
            if vus >= args.n_val:
                break
            d = json.loads(ligne)
            t = d.get("text", "").strip()
            if len(t.split()) < 4:
                continue
            try:
                items.append((Path(d["audio_filepath"]).stem, lire_wav(d["audio_filepath"]),
                              t.split()))
                vus += 1
            except Exception:
                continue
    if not items:
        raise SystemExit("aucun enregistrement lisible")
    print(f"{len(items)} enregistrements, "
          f"{sum(len(m) for _, _, m in items)} mots attendus au total\n", flush=True)

    rng = np.random.default_rng(args.graine)
    res = {"A": ([], []), "B": ([], []), "C": ([], [])}
    n_places = n_total = 0

    def scores(lp, spans, i, texte):
        s = spans[i]
        if s is None:
            return None
        f0, f1 = s
        tr = lp[f0:f1]
        n = max(1, f1 - f0)
        idm = sp.encode(texte)
        vv = viterbi_force(tr, idm)
        if vv is None:
            return None
        lab, _ = vv
        forced_v = float(tr[np.arange(len(lab)), lab].mean())
        forced_f = score_force(tr, idm) / n
        free = float(tr.max(axis=1).mean())
        alt = max((score_force(tr, sp.encode(a)) / n for a in alternatives(texte)),
                  default=NEG)
        return forced_v - free, forced_f - free, forced_f - alt

    for nom, pcm, mots in items:
        lp = logprobs_flux(sess, pcm)
        ids, bornes = [], []
        for m in mots:
            d0 = len(ids)
            ids += sp.encode(m)
            bornes.append((d0, len(ids)))
        v = viterbi_force(lp, ids)
        if v is None:
            continue
        _, tok = v
        spans = []
        for (a, b) in bornes:
            f = np.where((tok >= a) & (tok < b))[0]
            spans.append((int(f[0]), int(f[-1]) + 1) if len(f) else None)
        n_places += sum(1 for s in spans if s)
        n_total += len(mots)
        fautes = {i for i in range(len(mots)) if i % args.un_sur == 0}
        for i, m in enumerate(mots):
            if spans[i] is None:
                continue
            cible = m
            if i in fautes:
                f = fauter(m, rng)
                if f is None:
                    continue
                cible = f
            s = scores(lp, spans, i, cible)
            if s is None:
                continue
            for k, val in zip("ABC", s):
                res[k][0 if i in fautes else 1].append(val)
    print(f"{n_places}/{n_total} mots places par l'alignement\n", flush=True)

    print(f"{'regle':>6} {'ce qu elle compare':38} {'faute med':>10} "
          f"{'correct med':>12} {'ECART':>8}")
    print("-" * 80)
    libelle = {"A": "forced(Viterbi) - free   [app]",
               "B": "forced(forward) - free   [piste 0]",
               "C": "forced(att) - forced(alt) [piste 1]"}
    for k in "ABC":
        fa, co = res[k]
        if not fa or not co:
            continue
        print(f"{k:>6} {libelle[k]:38} {np.median(fa):>10.3f} "
              f"{np.median(co):>12.3f} {np.median(co)-np.median(fa):>8.3f}")
    print("-" * 80)

    print(f"\nDETECTION / COLLATERAL au meilleur seuil de chaque regle "
          f"({len(res['A'][0])} mots fautes, {len(res['A'][1])} corrects) :")
    print(f"{'regle':>6} {'seuil':>8} {'detection':>10} {'collateral':>11}")
    for k in "ABC":
        fa, co = np.array(res[k][0]), np.array(res[k][1])
        if not len(fa) or not len(co):
            continue
        best = None
        for s in np.quantile(np.concatenate([fa, co]), np.linspace(0.01, 0.99, 99)):
            det = float((fa < s).mean())
            col = float((co < s).mean())
            if best is None or (det - col) > (best[1] - best[2]):
                best = (s, det, col)
        print(f"{k:>6} {best[0]:>8.3f} {100*best[1]:>9.0f} % {100*best[2]:>10.1f} %")
    print("\nLes deux chiffres se lisent ENSEMBLE : une detection de 100 % "
          "obtenue en signalant tout le monde ne vaut rien.")


if __name__ == "__main__":
    main()
