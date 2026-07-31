#!/usr/bin/env python3
"""ETAPE 2a — apprendre la DECISION au lieu de la fabriquer a la main.

CE QUE LA MESURE DE L'ETAPE 1 A ETABLI. Entrainer l'encodeur et la tete lettres
sur des phrases fautees ameliore la REPRESENTATION (transcription des fautes
x1,8, charabia divise par 1,5) sans deplacer la DECISION (detection 26 % ->
28 %, dans le bruit). Raison structurelle : CTC optimise P(texte fourni | audio)
et ne COMPARE jamais deux hypotheses, alors que la decision de l'app est
exactement une comparaison. Le rapport faute/(faute+canonique) est reste a
23 % -> 22 %.

CE QUE FAIT CE SCRIPT. Il remplace la regle ECRITE A LA MAIN
(`gop = forced - free`, seuils -0,45 / -1,60, puis `gop = forced - forced(alt)`)
par un classifieur ENTRAINE sur les memes grandeurs. C'est un objectif
DISCRIMINATIF : il optimise directement « ce mot est-il conforme ? », qui est
la question posee, la ou CTC optimise une vraisemblance.

POURQUOI COMMENCER PAR LA, et non par la vraie tete sur l'etat de l'encodeur :
  - ca teste l'hypothese (« il faut un objectif discriminatif ») en quelques
    minutes au lieu d'un run, sur des donnees reelles ;
  - si ca marche, c'est DEPLOYABLE TEL QUEL -- quelques centaines de
    parametres appliques par mot, aucune passe d'encodeur en plus, aucun
    reexport de modele ;
  - si ca ne marche pas, ca dit que l'information n'est PAS dans les logprobs,
    et donc que la tete doit lire l'etat de l'encodeur -- ce qui oriente
    l'etape 2b au lieu de la lancer a l'aveugle.

PROTOCOLE. Les 189 premieres phrases sont celles TENUES A L'ECART de
l'entrainement de l'etape 1 : elles servent de test et ne sont jamais vues par
le classifieur. Le reste sert a l'entrainer. On mesure ce qu'on mesure depuis le
debut : DETECTION A 2 % DE COLLATERAL sur audio reellement faute.

Usage :
    PYTHONPATH=... /usr/bin/python3.14 tete_ecart_canonique.py \
        --modele <deploy/model.onnx> [--cache /tmp/.../feats.npz]
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

NEG = -1e30
_etat = {}

NOMS = ["forced_v", "forced_f", "free", "alt", "alt2", "gopA", "gopC",
        "marge_alt", "n_frames", "n_tokens", "entropie", "pic_blanc"]


def demarrer(modele, tokenizer):
    import onnxruntime as ort
    import sentencepiece as spm
    o = ort.SessionOptions()
    o.intra_op_num_threads = 1
    o.inter_op_num_threads = 1
    _etat["sess"] = ort.InferenceSession(modele, o, providers=["CPUExecutionProvider"])
    _etat["sp"] = spm.SentencePieceProcessor(model_file=tokenizer)


def caracteristiques(tr, sp, texte):
    """Tout ce qu'on sait deja sur ce mot, sans rien inventer de nouveau.

    Ce sont exactement les grandeurs que les regles A et C combinent a la main.
    Si le classifieur fait mieux qu'elles, c'est la COMBINAISON qui etait
    mauvaise, pas l'information.
    """
    from banc_regles_gop import viterbi_force
    from assainir_corpus_fautes import score_force
    from confusions_recitation import variantes
    n = max(1, tr.shape[0])
    idm = sp.encode(texte)
    vv = viterbi_force(tr, idm)
    if vv is None:
        return None
    lab, _ = vv
    forced_v = float(tr[np.arange(len(lab)), lab].mean())
    forced_f = score_force(tr, idm) / n
    free = float(tr.max(axis=1).mean())
    scores = sorted((score_force(tr, sp.encode(a)) / n for a in variantes(texte)),
                    reverse=True)
    alt = scores[0] if scores else NEG
    alt2 = scores[1] if len(scores) > 1 else alt
    p = np.exp(tr - tr.max(axis=1, keepdims=True))
    p /= p.sum(axis=1, keepdims=True)
    entropie = float(-(p * np.log(p + 1e-9)).sum(axis=1).mean())
    pic_blanc = float((tr.argmax(axis=1) == tr.shape[1] - 1).mean())
    return [forced_v, forced_f, free, alt, alt2, forced_v - free, forced_f - alt,
            alt - alt2, float(n), float(len(idm)), entropie, pic_blanc]


def traiter(r):
    from assainir_corpus_fautes import lire_wav
    from banc_regles_gop import logprobs_flux, spans_mots
    d = Path(r["_dossier"])
    sp, sess = _etat["sp"], _etat["sess"]
    mots = r["correct_text"].split()
    i = r["mot_index"]
    lignes = []
    for etat, clip in (("faute", r["clip_faute"]), ("correct", r["clip_correct"])):
        try:
            lp = logprobs_flux(sess, lire_wav(d / "wav" / clip))
        except Exception:
            continue
        spans = spans_mots(sp, lp, mots)
        if spans is None:
            continue
        for k, m in enumerate(mots):
            if spans[k] is None:
                continue
            f0, f1 = spans[k]
            c = caracteristiques(lp[f0:f1], sp, m)
            if c is None:
                continue
            lignes.append((c, 1 if (etat == "faute" and k == i) else 0, r["_test"]))
    return lignes


def entrainer(X, y, poids_pos, epochs=400, cache=32):
    """Un MLP minuscule -- l'objectif est de tester si la COMBINAISON peut etre
    apprise, pas de faire un gros modele. Quelques centaines de parametres."""
    import torch
    torch.manual_seed(0)
    m = torch.nn.Sequential(torch.nn.Linear(X.shape[1], cache), torch.nn.ReLU(),
                            torch.nn.Linear(cache, 1))
    opt = torch.optim.Adam(m.parameters(), lr=0.01, weight_decay=1e-4)
    xb = torch.tensor(X, dtype=torch.float32)
    yb = torch.tensor(y, dtype=torch.float32).unsqueeze(1)
    w = torch.tensor([poids_pos], dtype=torch.float32)
    perte = torch.nn.BCEWithLogitsLoss(pos_weight=w)
    for _ in range(epochs):
        opt.zero_grad()
        l = perte(m(xb), yb)
        l.backward()
        opt.step()
    n_par = sum(p.numel() for p in m.parameters())
    return m, n_par, float(l)


def detection_a_collateral(score_faute, score_correct, cible=0.02):
    """Le seul chiffre qui compte depuis le debut : a 2 % de mots corrects
    signales, quelle part des vraies fautes attrape-t-on ?"""
    if not len(score_faute) or not len(score_correct):
        return float("nan"), float("nan")
    s = np.quantile(score_correct, 1 - cible)
    return float((score_faute > s).mean()), float(s)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--dossier", default=str(BASE / "data" / "tts_phrases_concat"))
    p.add_argument("--modele", default="/tmp/claude-1000/modele/model.onnx")
    p.add_argument("--tokenizer",
                   default=str(BASE / "tokenizers" / "tajweed_bpe_v1" / "tokenizer.model"))
    p.add_argument("--n-test", type=int, default=189,
                   help="phrases tenues a l'ecart de l'etape 1 -- jamais vues ici non plus")
    p.add_argument("--travailleurs", type=int, default=12)
    p.add_argument("--cache", default=None)
    args = p.parse_args()

    d = Path(args.dossier)
    lignes = [json.loads(l) for l in open(d / "manifest.jsonl", encoding="utf-8")]
    for k, r in enumerate(lignes):
        r["_dossier"] = str(d)
        r["_test"] = k < args.n_test

    if args.cache and Path(args.cache).exists():
        z = np.load(args.cache)
        X, y, test = z["X"], z["y"], z["test"]
        print(f"caracteristiques relues : {X.shape[0]} mots")
    else:
        print(f"{len(lignes)} paires, extraction des caracteristiques...", flush=True)
        t0 = time.time()
        X, y, test = [], [], []
        with Pool(args.travailleurs, initializer=demarrer,
                  initargs=(args.modele, args.tokenizer)) as pool:
            for k, lot in enumerate(pool.imap_unordered(traiter, lignes, chunksize=4)):
                for c, lab, t in lot:
                    X.append(c)
                    y.append(lab)
                    test.append(t)
                if (k + 1) % 200 == 0:
                    print(f"  {k+1}/{len(lignes)}...", flush=True)
        X, y, test = np.array(X, dtype=np.float32), np.array(y), np.array(test)
        print(f"  {X.shape[0]} mots en {time.time()-t0:.0f} s")
        if args.cache:
            np.savez(args.cache, X=X, y=y, test=test)

    # PIEGE PAYE LE 2026-07-31 : un mot sans AUCUNE confusion plausible (ni
    # lettre confusable, ni harakat) recoit alt = -1e30. C'est FINI, donc
    # `isfinite` le laisse passer -- il detruit alors la normalisation
    # (« overflow encountered in square ») et fait diverger l'entrainement.
    # Symptome qui l'a revele : AUC de 0,000 sur une seule caracteristique,
    # ce qui est impossible autrement. Ces mots ne sont de toute facon pas
    # jugeables par la regle C : on les ECARTE, on ne les rafistole pas.
    ok = np.isfinite(X).all(axis=1) & (np.abs(X) < 1e6).all(axis=1)
    ecartes = (~ok).sum()
    X, y, test = X[ok], y[ok], test[ok]
    if ecartes:
        print(f"{ecartes} mots ecartes : aucune confusion plausible "
              f"({100*ecartes/len(ok):.1f} %)")
    mu, sd = X[~test].mean(0), X[~test].std(0) + 1e-6
    Xn = (X - mu) / sd
    ap, at = ~test, test
    print(f"\nentrainement : {ap.sum()} mots ({y[ap].sum()} fautes) | "
          f"test : {at.sum()} mots ({y[at].sum()} fautes)\n")

    import torch
    poids = float((y[ap] == 0).sum() / max(1, (y[ap] == 1).sum()))
    m, n_par, perte = entrainer(Xn[ap], y[ap], poids)
    with torch.no_grad():
        s = m(torch.tensor(Xn[at], dtype=torch.float32)).squeeze(1).numpy()

    print(f"{'decision':>34} {'detection a 2 % de collateral':>30}")
    print("-" * 66)
    # Les regles ecrites a la main, sur le MEME jeu de test.
    for nom, col, sens in (("regle A  forced(Viterbi) - free", "gopA", -1),
                           ("regle C  forced - forced(alt)", "gopC", -1)):
        v = X[at][:, NOMS.index(col)] * sens
        det, _ = detection_a_collateral(v[y[at] == 1], v[y[at] == 0])
        print(f"{nom:>34} {100*det:>28.0f} %")
    det, _ = detection_a_collateral(s[y[at] == 1], s[y[at] == 0])
    print(f"{'classifieur entraine':>34} {100*det:>28.0f} %")
    print("-" * 66)
    print(f"\n{n_par} parametres, perte finale {perte:.4f}")
    print("Les regles A et C sont evaluees sur le MEME jeu de test que le "
          "classifieur : la comparaison ne doit rien au decoupage.")


if __name__ == "__main__":
    main()
