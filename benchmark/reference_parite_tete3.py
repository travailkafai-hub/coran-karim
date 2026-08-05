#!/usr/bin/env python3
"""Produit le VECTEUR DE REFERENCE qui permet de verifier la parite Kotlin.

POURQUOI CE FICHIER EXISTE. `Tete3.kt` porte cet avertissement depuis sa
creation, et c'est le risque principal de toute la piste :

    « La tete a ete entrainee sur des caracteristiques calculees EN PYTHON. Le
      Kotlin doit les reproduire A L'IDENTIQUE. Une divergence ne provoque
      aucune erreur : elle rend simplement les poids denues de sens, et les
      31 % redeviennent du hasard. »

Sans vecteur de reference, implementer les caracteristiques cote Kotlin revient
a coder a l'aveugle puis a croire le resultat -- exactement le piege que le
projet a paye deux jours de suite (« le banc mesurait mon decoupage, pas
l'app »).

CE QUE CE SCRIPT ECRIT (`reference_tete3.json`) :
  - `logprobs`   : la matrice T x V exacte donnee en entree, en clair. Le
                   Kotlin doit partir des MEMES nombres, sinon on comparerait
                   deux calculs sur deux entrees differentes ;
  - `tokens`     : les identifiants du mot attendu, deja tokenises (la
                   tokenisation elle-meme n'est pas ce qu'on teste ici) ;
  - `variantes`  : les tokenisations des confusions, meme raison ;
  - `etat`       : l'etat d'encodeur des memes frames ;
  - `attendu`    : les 12 caracteristiques, valeur par valeur et nommees ;
  - `logit`      : la sortie finale de la tete sur ce vecteur.

Un test JVM qui rejoue ces entrees doit retrouver `attendu` a 1e-3 pres. S'il
echoue, la tete ne doit PAS tourner sur le telephone -- c'est le sens du garde
`verifierParite`.

PLUSIEURS CAS, PAS UN SEUL -- et c'est important. Un mot court a peu de frames
et deux tokens : son Viterbi ne remonte presque rien, et un backtrack faux y
passerait inapercu. On ecrit donc TOUS les mots jugeables de la phrase, du plus
court au plus long. Ce sont des mots REELS avec leurs vraies frames, donc les
cas limites (variantes non scorables, audio a peine suffisant) sont representes
au lieu d'etre imagines.
"""
import argparse
import json
import os
import sys
from pathlib import Path

os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import numpy as np
import torch

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from assainir_corpus_fautes import lire_wav  # noqa: E402
from banc_regles_gop import spans_mots  # noqa: E402
from confusions_recitation import variantes  # noqa: E402
from tete_encodeur_ecart import caracteristiques  # noqa: E402
from tete_ecart_canonique import NOMS  # noqa: E402


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--nemo", required=True)
    p.add_argument("--dossier", default=str(BASE / "data" / "tts_phrases_concat"))
    p.add_argument("--tete3", default=None,
                   help="tete3.json : si fourni, le logit attendu est calcule")
    p.add_argument("--sortie", default=str(BASE / "reference_tete3.json"))
    p.add_argument("--ligne", type=int, default=0)
    p.add_argument("--max-cas", type=int, default=5,
                   help="chaque cas pese ~90 ko : garder le fichier "
                        "lisible et versionnable")
    a = p.parse_args()

    import nemo.collections.asr as nemo_asr
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        a.nemo, map_location=dev)
    model.eval()
    model.preprocessor.featurizer.dither = 0.0
    sp = model.tokenizer.tokenizer

    d = Path(a.dossier)
    lignes = [json.loads(l) for l in open(d / "manifest.jsonl", encoding="utf-8")]
    r = lignes[a.ligne]
    mots = r["correct_text"].split()
    i = r["mot_index"]

    with torch.no_grad():
        pcm = lire_wav(d / "wav" / r["clip_faute"])
        sig = torch.tensor(pcm, device=dev).unsqueeze(0)
        ln = torch.tensor([len(pcm)], device=dev)
        feats, flen = model.preprocessor(input_signal=sig, length=ln)
        enc, _ = model.encoder(audio_signal=feats, length=flen)
        lg = model.ctc_decoder(encoder_output=enc)
        lp = torch.log_softmax(lg, dim=-1)[0].cpu().numpy()
        st = enc[0].transpose(0, 1).cpu().numpy()

    spans = spans_mots(sp, lp, mots)
    if spans is None:
        raise SystemExit("cette phrase ne s'aligne pas")

    t3 = None
    if a.tete3:
        t3 = json.loads(Path(a.tete3).read_text(encoding="utf-8"))
        mu = np.array(t3["normalisation"]["moyenne"])
        sd = np.array(t3["normalisation"]["ecart_type"])

    cas = []
    for j, mot in enumerate(mots):
        if spans[j] is None:
            continue
        f0, f1 = spans[j]
        # ── LE CONTRAT DOIT ETRE CLOS SUR LUI-MEME ────────────────────────────
        # Le JSON ne porte pas des flottants de precision infinie : il les
        # ARRONDIT. Si `attendu` etait calcule sur les valeurs exactes, le
        # Kotlin lirait des entrees LEGEREMENT differentes de celles qui ont
        # produit la reference -- et un vrai ecart de parite se confondrait
        # avec cet arrondi. On arrondit donc AVANT de calculer : le fichier
        # contient exactement ce qui a produit les valeurs attendues.
        tr = np.round(lp[f0:f1], 6)
        seg = np.round(st[f0:f1], 6)
        car = caracteristiques(tr, sp, mot)
        if car is None:
            continue                      # non jugeable : c'est un cas normal
        etat = np.concatenate([seg.mean(axis=0), seg.std(axis=0)])
        vecteur = np.concatenate([etat, np.asarray(car, dtype=np.float64)])
        c = {
            "mot": mot, "mot_index": j, "frames": [int(f0), int(f1)],
            "logprobs": [[float(x) for x in ligne] for ligne in tr],
            "etat": [[float(x) for x in ligne] for ligne in seg],
            "tokens": [int(t) for t in sp.encode(mot)],
            # Le TEXTE des variantes autant que leurs tokens : sans lui le test
            # ne verifie que le scoreur, jamais le GENERATEUR de confusions --
            # or c'est lui qui decide de `alt` et `alt2`.
            "variantes_texte": list(variantes(mot)),
            "variantes": [[int(t) for t in sp.encode(v)] for v in variantes(mot)],
            "attendu": {n: round(float(v), 6) for n, v in zip(NOMS, car)},
            "taille_vecteur": int(len(vecteur)),
        }
        if t3 is not None:
            if len(mu) != len(vecteur):
                raise SystemExit(
                    f"tete3.json attend {len(mu)} caracteristiques, le vecteur "
                    f"en a {len(vecteur)} -- ce n'est pas la bonne tete")
            x = (vecteur - mu) / sd
            c1, c2 = t3["couches"][0], t3["couches"][1]
            h = np.maximum(np.array(c1["poids"]) @ x + np.array(c1["biais"]), 0)
            c["logit_attendu"] = round(
                float(np.array(c2["poids"])[0] @ h + c2["biais"][0]), 6)
        cas.append(c)
        if len(cas) >= a.max_cas:
            break

    if not cas:
        raise SystemExit("aucun mot jugeable sur cette ligne")

    ref = {
        "commentaire": "Vecteur de reference pour Tete3TraitsTest (parite "
                       "Python/Kotlin). Ne pas regenerer sans raison : un test "
                       "qui change de reference ne teste plus rien.",
        "source": {"ligne": a.ligne, "clip": r["clip_faute"],
                   "phrase": r["correct_text"]},
        "noms": list(NOMS),
        "seuil_2pct": (t3 or {}).get("seuils_mesures", {}).get("collateral_2pct"),
        "cas": cas,
    }

    Path(a.sortie).write_text(json.dumps(ref, ensure_ascii=False), encoding="utf-8")
    print(f"phrase : {r['correct_text']}")
    for c in cas:
        print(f"\n  mot {c['mot_index']:2d} {c['mot']!r} "
              f"frames {c['frames'][0]}..{c['frames'][1]} "
              f"({len(c['tokens'])} tokens, {len(c['variantes'])} variantes)")
        for n in NOMS:
            print(f"      {n:12s} {c['attendu'][n]:12.6f}")
        if "logit_attendu" in c:
            print(f"      {'LOGIT':12s} {c['logit_attendu']:12.6f}")
    print(f"\n-> {a.sortie}  ({Path(a.sortie).stat().st_size/1e6:.2f} Mo, "
          f"{len(cas)} cas)")

if __name__ == "__main__":
    main()
