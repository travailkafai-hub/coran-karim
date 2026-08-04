#!/usr/bin/env python3
"""TETE 3 SUR AUDIO REEL -- genere des exemples de deviation par RE-ETIQUETAGE
du texte canonique, pas par synthese de faute.

IDEE (utilisateur, 2026-08-04). Le mecanisme d'entrainement de
tete_encodeur_ecart.py ne regarde JAMAIS ce que l'audio dit reellement : il
force l'alignement/score contre le texte CANONIQUE declare, et le label
`faute=1` vient uniquement du fait que ce texte differe du mot reellement
prononce a cette position (verifie dans caracteristiques()/la boucle
principale). Rien n'exige que l'audio soit synthetique.

CONSEQUENCE : on prend un clip REEL du corpus d'entrainement ASR (201 956
clips, recitateurs professionnels, texte exact deja connu), et pour UN mot on
declare un texte canonique FAUX (une variante -- lettre, harakat, omission,
insertion). Le mecanisme produit un exemple `faute=1` propre, sans aucune
synthese ni probleme de rendu TTS (ce qui a tue ض->ظ ce matin, 2 % de
rendement). Le reste de la phrase garde son texte reel, donc reste un exemple
`correct=0` valide.

TROIS REGLES IMPOSEES PAR L'UTILISATEUR (2026-08-04) :
  1. Pas seulement les lettres CONFUSABLES (proches) -- aussi des substitutions
     eloignees (ex. و->ف), des VRAIES fautes structurelles.
  2. Omission (lettre manquante) et insertion (lettre en trop), pas seulement
     substitution.
  3. JAMAIS toucher la DERNIERE harakat d'un mot : en fin de mot/verset, le
     recitateur peut legitimement marquer une pause (waqf) et la remplacer par
     un soukoun -- ce n'est pas une faute, l'etiqueter comme telle empoisonne
     l'entrainement.

Usage :
    PYTHONPATH=... /usr/bin/python3.14 tete3_audio_reel.py \
        --nemo benchmark/models/fastconformer-final-v1/causal-final.nemo \
        --manifest nemo_manifests_dual/train_manifest_final.jsonl \
        --n-clips 4000 --cache /tmp/claude-1000/etats_encodeur_reel.npz
"""
import argparse
import json
import os
import random
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
from tete_encodeur_ecart import caracteristiques  # noqa: E402

SHORT_HARAKAT = ["َ", "ُ", "ِ", "ْ"]  # fatha damma kasra sukun

# Paires DURES, memes que generate_phrases_concat.py -- pour une mesure
# comparable au pipeline TTS (pas de substitution eloignee/triviale).
CONFUSABLES_DURES = [
    ("ط", "ت"), ("ه", "ح"), ("ك", "ق"), ("ق", "ك"),
    ("ح", "ه"), ("ت", "ط"), ("ذ", "ز"), ("د", "ض"),
    ("س", "ص"), ("ض", "د"), ("ع", "ء"), ("ص", "س"),
    ("ج", "ح"), ("ح", "خ"), ("ج", "خ"),
    ("ض", "ظ"), ("ظ", "ض"), ("ث", "س"), ("س", "ث"),
]
LETTRES = list("ابتثجحخدذرز"
               "سشصضطظعغفقك"
               "لمنهويءؤئةى")


def variante_large(mot, rng, dur_seulement=False):
    """Une variante aleatoire du mot -- substitution (proche ou eloignee),
    harakat (JAMAIS la derniere position), omission, ou insertion.
    @return (texte_variant, categorie, detail) ou None si rien n'est possible."""
    consonnes = [k for k, c in enumerate(mot) if c in LETTRES]
    pos_harakat = [k for k, c in enumerate(mot) if c in SHORT_HARAKAT]
    derniere_harakat = pos_harakat[-1] if pos_harakat else -1
    pos_harakat_ok = [k for k in pos_harakat if k != derniere_harakat]

    # En mode dur, on ne garde que les paires DURES (memes que le TTS) et le
    # harakat -- pas de substitution eloignee/triviale, pas d'omission/insertion
    # (qui changent la longueur du texte "canonique", signal facile a part).
    subs_dures = []
    if dur_seulement:
        for a, b in CONFUSABLES_DURES:
            for src, dst in ((a, b), (b, a)):
                j = mot.find(src)
                if j >= 0:
                    subs_dures.append((j, src, dst))

    choix = []
    if dur_seulement:
        if subs_dures:
            choix += ["substitution_dure"] * 3
        if pos_harakat_ok:
            choix += ["harakat"] * 2
    else:
        if consonnes:
            choix += ["substitution"] * 3
        if pos_harakat_ok:
            choix += ["harakat"] * 2
        if consonnes:
            choix += ["omission", "insertion"]
    if not choix:
        return None
    cat = rng.choice(choix)

    if cat == "substitution_dure":
        j, src, dst = rng.choice(subs_dures)
        return mot[:j] + dst + mot[j + 1:], "substitution_dure", f"{src}->{dst}@{j}"
    if cat == "substitution":
        k = rng.choice(consonnes)
        autres = [c for c in LETTRES if c != mot[k]]
        dst = rng.choice(autres)
        return mot[:k] + dst + mot[k + 1:], "substitution", f"{mot[k]}->{dst}@{k}"
    if cat == "harakat":
        k = rng.choice(pos_harakat_ok)
        autres = [h for h in SHORT_HARAKAT if h != mot[k]]
        dst = rng.choice(autres)
        return mot[:k] + dst + mot[k + 1:], "harakat", f"harakat@{k}:{mot[k]}->{dst}"
    if cat == "omission":
        k = rng.choice(consonnes)
        return mot[:k] + mot[k + 1:], "omission", f"omission@{k}:{mot[k]}"
    if cat == "insertion":
        k = rng.choice(consonnes + [len(mot)])
        c = rng.choice(LETTRES)
        return mot[:k] + c + mot[k:], "insertion", f"insertion@{k}:{c}"
    return None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--nemo", required=True)
    p.add_argument("--manifest", default=str(BASE / "nemo_manifests_dual" / "train_manifest_final.jsonl"))
    p.add_argument("--n-clips", type=int, default=4000)
    p.add_argument("--n-test", type=int, default=300)
    p.add_argument("--seed", type=int, default=13)
    p.add_argument("--cache", default="/tmp/claude-1000/etats_encodeur_reel.npz")
    p.add_argument("--dur-seulement", action="store_true", help="restreint aux paires CONFUSABLES + harakat, comparable au pipeline TTS")
    args = p.parse_args()

    import nemo.collections.asr as nemo_asr
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"chargement du modele sur {dev}...", flush=True)
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(args.nemo, map_location=dev)
    model.eval()
    model.preprocessor.featurizer.dither = 0.0
    sp = model.tokenizer.tokenizer

    rng = random.Random(args.seed)
    lignes = [json.loads(l) for l in open(args.manifest, encoding="utf-8")]
    rng.shuffle(lignes)
    lignes = lignes[:args.n_clips]
    print(f"{len(lignes)} clips reels echantillonnes sur {sum(1 for _ in open(args.manifest))}", flush=True)

    E, X, y, test = [], [], [], []
    t0 = time.time()
    n_variantes_impossibles = 0
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
            # Un seul mot cible par clip (comme le pipeline TTS : une faute par
            # phrase) -- tire au hasard parmi les mots correctement segmentes.
            candidats = [j for j, s in enumerate(spans) if s is not None]
            if not candidats:
                continue
            i = rng.choice(candidats)
            f0, f1 = spans[i]
            variante = variante_large(mots[i], rng, dur_seulement=args.dur_seulement)
            if variante is None:
                n_variantes_impossibles += 1
                continue
            texte_variant, cat, detail = variante

            # FAUTE=1 : audio reel de mots[i], etiquette canonique = variante
            c_faute = caracteristiques(lp[f0:f1], sp, texte_variant)
            if c_faute is not None:
                # ETAT RICHE : moyenne ET ecart-type sur les frames du mot (2026-08-05).
                # La moyenne seule DETRUIT la structure temporelle avant meme d'atteindre la
                # tete -- or une deviation est souvent une IRREGULARITE dans le mot (une lettre
                # qui derape), pas un deplacement de son centre de gravite. L'ecart-type par
                # dimension rend cette variabilite interne, pour le meme cout de calcul.
                _seg = st[f0:f1]
                E.append(np.concatenate([_seg.mean(axis=0), _seg.std(axis=0)]))
                X.append(c_faute)
                y.append(1)
                test.append(k < args.n_test)
            # CORRECT=0 : meme audio, etiquette canonique = le VRAI mot
            c_correct = caracteristiques(lp[f0:f1], sp, mots[i])
            if c_correct is not None:
                # ETAT RICHE : moyenne ET ecart-type sur les frames du mot (2026-08-05).
                # La moyenne seule DETRUIT la structure temporelle avant meme d'atteindre la
                # tete -- or une deviation est souvent une IRREGULARITE dans le mot (une lettre
                # qui derape), pas un deplacement de son centre de gravite. L'ecart-type par
                # dimension rend cette variabilite interne, pour le meme cout de calcul.
                _seg = st[f0:f1]
                E.append(np.concatenate([_seg.mean(axis=0), _seg.std(axis=0)]))
                X.append(c_correct)
                y.append(0)
                test.append(k < args.n_test)

            if (k + 1) % 200 == 0:
                dt = time.time() - t0
                print(f"  {k+1}/{len(lignes)}  ({dt/(k+1):.2f} s/clip, "
                      f"{len(y)} exemples, {n_variantes_impossibles} sans variante)", flush=True)

    E = np.array(E, dtype=np.float32)
    X = np.array(X, dtype=np.float32)
    y, test = np.array(y), np.array(test)
    np.savez(args.cache, E=E, X=X, y=y, test=test)
    print(f"\n{E.shape[0]} exemples ({int(y.sum())} fautes) en {time.time()-t0:.0f} s -> {args.cache}")


if __name__ == "__main__":
    main()
