#!/usr/bin/env python3
"""Compare l'ancienne et la nouvelle tete 3 Hafs, PAR CATEGORIE de faute.

Necessaire parce que `recalibrer_tete3.py` mesure sur le test split DE SON
PROPRE cache -- comparer son chiffre a celui d'un autre cache (l'ancien
tete3_hafs.json) n'est pas valide (le script le dit lui-meme : « ne pas les
reafficher pour un autre cache »). Ce script recalcule le MEME jeu de test
(meme seed, memes clips, meme methode que tete3_audio_reel.py) mais garde la
CATEGORIE de chaque variante, et score les deux tetes dessus -- seule facon
de savoir si le gain est reel et OU il se trouve (particule vs reste).
"""
import argparse
import json
import random
import sys
import time
from pathlib import Path

import numpy as np
import torch

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from assainir_corpus_fautes import lire_wav  # noqa: E402
from banc_regles_gop import spans_mots  # noqa: E402
from tete_encodeur_ecart import caracteristiques  # noqa: E402
from tete3_audio_reel import variante_large  # noqa: E402


def charger_tete(path):
    d = json.loads(Path(path).read_text(encoding="utf-8"))
    mu = np.array(d["normalisation"]["moyenne"])
    sd = np.array(d["normalisation"]["ecart_type"])
    c1, c2 = d["couches"][0], d["couches"][1]
    W0, b0 = np.array(c1["poids"]), np.array(c1["biais"])
    W1, b1 = np.array(c2["poids"]), np.array(c2["biais"])
    return mu, sd, W0, b0, W1, b1


def logit(vecteur, tete):
    mu, sd, W0, b0, W1, b1 = tete
    x = (vecteur - mu) / sd
    h = np.maximum(W0 @ x + b0, 0)
    return float(W1[0] @ h + b1[0])


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--nemo", required=True)
    p.add_argument("--manifest", default=str(BASE / "nemo_manifests_dual" / "train_manifest_final.jsonl"))
    p.add_argument("--n-clips", type=int, default=40000, help="doit matcher la generation d'origine")
    p.add_argument("--n-test", type=int, default=3000, help="doit matcher la generation d'origine")
    p.add_argument("--seed", type=int, default=13, help="doit matcher la generation d'origine")
    p.add_argument("--tete-ancienne", required=True)
    p.add_argument("--tete-nouvelle", required=True)
    a = p.parse_args()

    import os
    os.environ["USE_TF"] = "0"
    os.environ["USE_JAX"] = "0"
    import nemo.collections.asr as nemo_asr
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        a.nemo, map_location=dev, strict=False)
    model.eval()
    model.preprocessor.featurizer.dither = 0.0
    sp = model.tokenizer.tokenizer

    ancienne = charger_tete(a.tete_ancienne)
    nouvelle = charger_tete(a.tete_nouvelle)

    rng = random.Random(a.seed)
    lignes = [json.loads(l) for l in open(a.manifest, encoding="utf-8")]
    rng.shuffle(lignes)
    lignes = lignes[:a.n_clips][:a.n_test]  # meme prefixe que le test split d'origine
    print(f"{len(lignes)} clips de test (meme seed/prefixe que la generation)", flush=True)

    # cas[cat] -> liste de (score_ancienne, score_nouvelle) pour faute=1
    # + une entree speciale "correct" pour y=0 (toutes categories confondues)
    resultats = {"correct": {"ancienne": [], "nouvelle": []}}
    t0 = time.time()
    with torch.no_grad():
        for k, r in enumerate(lignes):
            mots = r["text"].split()
            if len(mots) < 2:
                continue
            try:
                pcm = lire_wav(Path(r["audio_filepath"]))
            except Exception:
                continue
            try:
                sig = torch.tensor(pcm, device=dev).unsqueeze(0)
                ln = torch.tensor([len(pcm)], device=dev)
                feats, flen = model.preprocessor(input_signal=sig, length=ln)
                enc, _ = model.encoder(audio_signal=feats, length=flen)
                lg = model.ctc_decoder(encoder_output=enc)
                lp = torch.log_softmax(lg, dim=-1)[0].cpu().numpy()
                st = enc[0].transpose(0, 1).cpu().numpy()
            except Exception:
                continue
            spans = spans_mots(sp, lp, mots)
            if spans is None:
                continue
            candidats = [j for j, s in enumerate(spans) if s is not None]
            if not candidats:
                continue
            i = rng.choice(candidats)
            f0, f1 = spans[i]
            variante = variante_large(mots[i], rng)
            if variante is None:
                continue
            texte_variant, cat, detail = variante

            c_faute = caracteristiques(lp[f0:f1], sp, texte_variant)
            if c_faute is not None:
                _seg = st[f0:f1]
                vec = np.concatenate([_seg.mean(axis=0), _seg.std(axis=0),
                                       np.asarray(c_faute, dtype=np.float64)])
                resultats.setdefault(cat, {"ancienne": [], "nouvelle": []})
                resultats[cat]["ancienne"].append(logit(vec, ancienne))
                resultats[cat]["nouvelle"].append(logit(vec, nouvelle))

            c_correct = caracteristiques(lp[f0:f1], sp, mots[i])
            if c_correct is not None:
                _seg = st[f0:f1]
                vec = np.concatenate([_seg.mean(axis=0), _seg.std(axis=0),
                                       np.asarray(c_correct, dtype=np.float64)])
                resultats["correct"]["ancienne"].append(logit(vec, ancienne))
                resultats["correct"]["nouvelle"].append(logit(vec, nouvelle))

            if (k + 1) % 500 == 0:
                print(f"  {k+1}/{len(lignes)}  ({time.time()-t0:.0f}s)", flush=True)

    # seuil : 0.0 sur le logit brut (equivalent sigmoid 0.5), comme le
    # regime "seuil brut" deja utilise ailleurs dans ce chantier
    print(f"\n{'categorie':<24s} {'n':>6s} {'rappel_ancienne':>16s} {'rappel_nouvelle':>16s}")
    print("-" * 66)
    for cat, d in sorted(resultats.items()):
        if cat == "correct":
            continue
        n = len(d["ancienne"])
        if n == 0:
            continue
        rec_a = 100 * sum(1 for s in d["ancienne"] if s > 0) / n
        rec_n = 100 * sum(1 for s in d["nouvelle"] if s > 0) / n
        print(f"{cat:<24s} {n:>6d} {rec_a:>15.1f}% {rec_n:>15.1f}%")

    c = resultats["correct"]
    n = len(c["ancienne"])
    fp_a = 100 * sum(1 for s in c["ancienne"] if s > 0) / n if n else 0
    fp_n = 100 * sum(1 for s in c["nouvelle"] if s > 0) / n if n else 0
    print("-" * 66)
    print(f"{'correct (faux positifs)':<24s} {n:>6d} {fp_a:>15.1f}% {fp_n:>15.1f}%")


if __name__ == "__main__":
    main()
