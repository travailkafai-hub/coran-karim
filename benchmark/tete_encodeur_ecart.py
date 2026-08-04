#!/usr/bin/env python3
"""ETAPE 2b — la tete lit l'ETAT DE L'ENCODEUR, pas ses logprobs.

CE QUE L'ETAPE 2a A ETABLI. Un classifieur discriminatif entraine sur les
grandeurs deja extraites (forced, free, meilleure confusion, duree, entropie...)
separe MIEUX globalement que la regle ecrite a la main -- AUC 0,748 -> 0,792,
+6 points a 10 % de collateral -- mais ne gagne RIEN au point de fonctionnement
vise : 26 % contre 28 % a 2 % de collateral. Cibler la queue de la distribution
(negatifs durs) fait pire encore (AUC 0,665).

Conclusion : ce n'est pas la COMBINAISON qui etait mauvaise, c'est que les
logprobs ont deja jete l'information. Ils sont la projection de 512 dimensions
sur 1025 classes, apprise pour TRANSCRIRE -- rien ne garantit qu'elle conserve
de quoi juger une deviation. D'ou cette etape : la tete lit les 512 dimensions.

L'ENCODEUR EST GELE. Il n'est jamais mis a jour ici : le val_wer_ctc de 0,181
acquis a l'etape 1 est donc protege par construction, pas par surveillance.
C'est tout l'interet d'une tete -- et c'est aussi pourquoi elle coute < 1 % a
l'execution (l'encodeur tourne une fois, la tete est une couche lineaire).

CONDITIONNEE SUR LA CIBLE. Une tete qui ne lirait que l'acoustique ne peut pas
repondre : un ص correct et un س correct sonnent tous deux « corrects », seule la
cible dit lequel etait attendu. On lui donne donc l'etat de l'encodeur moyenne
sur les frames du mot ET les grandeurs conditionnees par la cible de l'etape 2a.

PROTOCOLE INCHANGE, c'est ce qui rend les chiffres comparables : les 189
premieres phrases sont tenues a l'ecart (elles l'etaient deja de l'etape 1), et
on lit DETECTION A 2 % DE COLLATERAL sur audio reellement faute.

Usage :
    PYTHONPATH=... /usr/bin/python3.14 tete_encodeur_ecart.py \
        --nemo benchmark/models/fastconformer-causal-v4-phrases/causal-final.nemo
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path

os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import numpy as np
import torch

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from assainir_corpus_fautes import lire_wav, score_force  # noqa: E402
from banc_regles_gop import spans_mots, viterbi_force  # noqa: E402
from confusions_recitation import variantes  # noqa: E402
from tete_ecart_canonique import (NOMS, detection_a_collateral,  # noqa: E402
                                  entrainer)

NEG = -1e30


def caracteristiques(tr, sp, texte):
    """Les 12 grandeurs de l'etape 2a -- conservees telles quelles pour que la
    comparaison porte uniquement sur l'AJOUT de l'etat d'encodeur."""
    n = max(1, tr.shape[0])
    idm = sp.encode(texte)
    vv = viterbi_force(tr, idm)
    if vv is None:
        return None
    lab, _ = vv
    forced_v = float(tr[np.arange(len(lab)), lab].mean())
    forced_f = score_force(tr, idm) / n
    free = float(tr.max(axis=1).mean())
    # VARIANTES NON SCORABLES : EXCLUES, PAS NOTEES -1e30 (correctif 2026-08-05).
    #
    # `score_force` rend la sentinelle NEG = -1e30 quand l'audio est trop court
    # pour la sequence de tokens (`T < (S+1)//2`) -- une variante plus longue
    # que le mot n'a alors AUCUN alignement possible. C'est un « non mesurable »,
    # pas un « tres mauvais score ». En le divisant par n on obtenait des
    # caracteristiques a -1e29, que le filtre `|X| < 1e6` de main() jetait
    # ensuite : 406 exemples sur 3675, soit 11 % du jeu d'entrainement PERDUS
    # en silence -- et parmi eux des fautes, donc de la donnee rare.
    # On ecarte donc ces variantes du concours au lieu de les faire concourir
    # avec un score aberrant.
    scores = sorted((v for v in (score_force(tr, sp.encode(a)) / n
                                 for a in variantes(texte))
                     if v > NEG / 2), reverse=True)
    if not scores:
        return None                      # aucune confusion plausible : non jugeable
    alt = scores[0]
    alt2 = scores[1] if len(scores) > 1 else alt
    p = np.exp(tr - tr.max(axis=1, keepdims=True))
    p /= p.sum(axis=1, keepdims=True)
    entropie = float(-(p * np.log(p + 1e-9)).sum(axis=1).mean())
    pic_blanc = float((tr.argmax(axis=1) == tr.shape[1] - 1).mean())
    # ── LE MINIMUM, PAS SEULEMENT LA MOYENNE (2026-08-05) ──────────────────
    #
    # MEME DEFAUT QUE L'ETAT D'ENCODEUR MOYENNE, et meme correctif. Une faute
    # ne porte le plus souvent que sur UNE lettre : sur un mot de six tokens,
    # cinq restent parfaits et diluent le sixieme dans la moyenne. `forced_v`
    # est donc structurellement sourd a ce qu'on cherche -- il mesure la sante
    # GENERALE du mot, quand la question est « y a-t-il un endroit ou ca
    # casse ». Le minimum le long du chemin force repond a cette question-la.
    # `forced_v - fmin` dit de combien le pire point s'ecarte du reste : c'est
    # le creux, independamment du niveau general du mot.
    par_frame = tr[np.arange(len(lab)), lab]
    fmin = float(par_frame.min())
    fp10 = float(np.percentile(par_frame, 10))
    creux = forced_v - fmin
    return [forced_v, forced_f, free, alt, alt2, forced_v - free, forced_f - alt,
            alt - alt2, float(n), float(len(idm)), entropie, pic_blanc,
            fmin, fp10, creux]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--nemo", default=str(
        BASE / "models" / "fastconformer-causal-v4-phrases" / "causal-final.nemo"))
    p.add_argument("--dossier", default=str(BASE / "data" / "tts_phrases_concat"))
    p.add_argument("--n-test", type=int, default=189)
    p.add_argument("--cache", default="/tmp/claude-1000/etats_encodeur.npz")
    args = p.parse_args()

    d = Path(args.dossier)
    lignes = [json.loads(l) for l in open(d / "manifest.jsonl", encoding="utf-8")]

    if Path(args.cache).exists():
        z = np.load(args.cache)
        E, X, y, test = z["E"], z["X"], z["y"], z["test"]
        print(f"relu du cache : {E.shape[0]} mots, etat d'encodeur {E.shape[1]}D")
    else:
        import nemo.collections.asr as nemo_asr
        dev = "cuda" if torch.cuda.is_available() else "cpu"
        print(f"chargement du modele sur {dev}...", flush=True)
        model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
            args.nemo, map_location=dev)
        model.eval()
        model.preprocessor.featurizer.dither = 0.0
        sp = model.tokenizer.tokenizer

        E, X, y, test = [], [], [], []
        t0 = time.time()
        with torch.no_grad():
            for k, r in enumerate(lignes):
                mots = r["correct_text"].split()
                i = r["mot_index"]
                for etat, clip in (("faute", r["clip_faute"]),
                                   ("correct", r["clip_correct"])):
                    try:
                        pcm = lire_wav(d / "wav" / clip)
                    except Exception:
                        continue
                    sig = torch.tensor(pcm, device=dev).unsqueeze(0)
                    ln = torch.tensor([len(pcm)], device=dev)
                    feats, flen = model.preprocessor(input_signal=sig, length=ln)
                    enc, _ = model.encoder(audio_signal=feats, length=flen)
                    lg = model.ctc_decoder(encoder_output=enc)
                    lp = torch.log_softmax(lg, dim=-1)[0].cpu().numpy()
                    st = enc[0].transpose(0, 1).cpu().numpy()     # (T, 512)
                    spans = spans_mots(sp, lp, mots)
                    if spans is None:
                        continue
                    for j, m in enumerate(mots):
                        if spans[j] is None:
                            continue
                        f0, f1 = spans[j]
                        c = caracteristiques(lp[f0:f1], sp, m)
                        if c is None:
                            continue
                        # ETAT RICHE : moyenne ET ecart-type sur les frames du mot (2026-08-05).
                        # La moyenne seule DETRUIT la structure temporelle avant meme d'atteindre la
                        # tete -- or une deviation est souvent une IRREGULARITE dans le mot (une lettre
                        # qui derape), pas un deplacement de son centre de gravite. L'ecart-type par
                        # dimension rend cette variabilite interne, pour le meme cout de calcul.
                        _seg = st[f0:f1]
                        E.append(np.concatenate([_seg.mean(axis=0), _seg.std(axis=0)]))
                        X.append(c)
                        y.append(1 if (etat == "faute" and j == i) else 0)
                        test.append(k < args.n_test)
                if (k + 1) % 200 == 0:
                    print(f"  {k+1}/{len(lignes)}  ({(time.time()-t0)/(k+1):.2f} s/paire)",
                          flush=True)
        E = np.array(E, dtype=np.float32)
        X = np.array(X, dtype=np.float32)
        y, test = np.array(y), np.array(test)
        np.savez(args.cache, E=E, X=X, y=y, test=test)
        print(f"  {E.shape[0]} mots en {time.time()-t0:.0f} s")

    ok = np.isfinite(X).all(axis=1) & (np.abs(X) < 1e6).all(axis=1) \
        & np.isfinite(E).all(axis=1)
    E, X, y, test = E[ok], X[ok], y[ok], test[ok]
    ap, at = ~test, test
    print(f"\nentrainement {ap.sum()} mots ({y[ap].sum()} fautes) | "
          f"test {at.sum()} mots ({y[at].sum()} fautes)\n")

    def norm(A):
        mu, sd = A[ap].mean(0), A[ap].std(0) + 1e-6
        return (A - mu) / sd

    def auc(sf, sc):
        a = np.concatenate([sf, sc])
        r = a.argsort().argsort() + 1
        return (r[:len(sf)].sum() - len(sf) * (len(sf) + 1) / 2) / (len(sf) * len(sc))

    def ligne(nom, s):
        sf, sc = s[y[at] == 1], s[y[at] == 0]
        det = [detection_a_collateral(sf, sc, c)[0] for c in (0.02, 0.05, 0.10)]
        print(f"{nom:>36} {auc(sf, sc):>7.3f} {100*det[0]:>7.0f}% "
              f"{100*det[1]:>7.0f}% {100*det[2]:>8.0f}%")

    print(f"{'decision':>36} {'AUC':>7} {'det@2%':>8} {'det@5%':>8} {'det@10%':>9}")
    print("-" * 72)
    ligne("regle C (reference, a la main)", -X[at][:, NOMS.index("gopC")])
    poids = float((y[ap] == 0).sum() / max(1, (y[ap] == 1).sum()))
    for nom, A in (("tete sur 12 scores (2a)", norm(X)),
                   ("tete sur ETAT ENCODEUR seul", norm(E)),
                   ("tete sur ETAT + scores (2b)", np.hstack([norm(E), norm(X)]))):
        m, npar, _ = entrainer(A[ap], y[ap], poids, epochs=1200)
        with torch.no_grad():
            s = m(torch.tensor(A[at], dtype=torch.float32)).squeeze(1).numpy()
        ligne(f"{nom} [{npar} par.]", s)
    print("-" * 72)
    print("\nL'encodeur n'est JAMAIS mis a jour ici : le val_wer_ctc de 0,181 "
          "est protege par construction.")


if __name__ == "__main__":
    main()
