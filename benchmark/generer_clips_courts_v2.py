#!/usr/bin/env python3
"""GENERE des fragments COURTS via ALIGNEMENT FORCE REEL (pas d'estimation externe).

Version 2 -- la v1 (`generer_clips_courts.py`) utilisait des PROPORTIONS
empruntees a `word_timings_ref.json` (mediane murattal sur quran.com d'AUTRES
recitateurs), mises a l'echelle de la duree du clip. Mesure du 2026-07-31 sur
audio REEL, apres coup : WER 36-37 % meme sur des fragments "proprement
bornes", jusqu'a 600 % sur certains -- et le retrait de 9 recitateurs
identifies comme mal etiquetes n'a presque rien change (37,2 % -> 36,0 %). La
cause n'etait donc PAS les donnees sources, mais la methode d'estimation
elle-meme : une proportion empruntee a une AUTRE recitation ne transfere pas
de facon fiable, meme pour des recitateurs par ailleurs corrects (Dussary
12,5 %, mais Salaah_AbdulRahman_Bukhatir 54,5 %, khalefa_al_tunaiji 72,7 % --
tous "normaux" sur les clips longs originaux, non decoupes).

── LA CORRECTION : ALIGNEMENT FORCE SUR LE CLIP LUI-MEME ──────────────────
`spans_mots()` (deja dans le projet, `banc_regles_gop.py`) aligne la cible
texte sur les LOGPROBS REELS de CE clip via Viterbi CTC contraint. La
frontiere vient du modele qui ECOUTE cet audio precis, pas d'une moyenne
statistique empruntee ailleurs. C'est plus lourd (une passe encodeur par
clip, ~50k clips) mais c'est la seule methode qui a une chance d'etre fiable.

── VERIFICATION AVANT DE LANCER EN GRAND (lecon du 2026-07-31) ────────────
Ne JAMAIS generer 100k+ fragments avant d'avoir mesure la qualite sur un petit
echantillon par decodage reel + WER norme. C'est cette etape qui a ete sautee
pour la v1, et 18 Go ont ete generes et entraines a moitie sur des donnees
fausses avant que quelqu'un demande une verification.

── CE QUI RESTE IDENTIQUE A LA v1 ──────────────────────────────────────────
- Coupe en plein mot pour une partie des fragments, cible texte EXCLUANT le
  mot tronque (decision utilisateur du 2026-07-31, cf. docstring v1).
- Recitateurs de `recitateurs_exclus.py` ecartes par precaution (leur defaut
  etait un vrai mismatch audio/texte a la source, independant de la methode
  d'alignement -- pas de raison de les reintroduire ici).
"""
import os

os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import argparse
import json
import random
import sys
from pathlib import Path

import numpy as np
import torch

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from banc_regles_gop import spans_mots, viterbi_force  # noqa: E402
from frontieres_ctc import frontieres_par_blanc  # noqa: E402
from recitateurs_exclus import est_exclu  # noqa: E402

TRAIN_MANIFEST = BASE / "nemo_manifests_dual" / "train_manifest.jsonl"
OUT_DIR = BASE / "data" / "clips_courts_v3"
OUT_MANIFEST = OUT_DIR / "manifest.jsonl"

import re
_LETTRE_AR = re.compile(r"[ء-يٮ-ۓ]")


def est_un_mot(tok: str) -> bool:
    return bool(_LETTRE_AR.search(tok))


def lire_wav16(p):
    import soundfile as sf
    x, sr = sf.read(str(p), dtype="float32")
    if x.ndim > 1:
        x = x.mean(axis=1)
    if sr != 16000:
        n = int(round(len(x) * 16000 / sr))
        x = np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x).astype(np.float32)
    return x


def bornes_depuis_spans(spans, frame_sec):
    """[(f0,f1) ou None, ...] -> bornes CUMULEES en secondes (n_mots+1
    valeurs), en comblant les mots non alignes (span None) par interpolation
    lineaire entre les voisins alignes -- rare mais doit rester exploitable
    plutot que de jeter tout le clip."""
    n = len(spans)
    debuts = [None] * n
    fins = [None] * n
    for i, s in enumerate(spans):
        if s is not None:
            debuts[i] = s[0] * frame_sec
            fins[i] = s[1] * frame_sec
    if all(d is None for d in debuts):
        return None
    # bornes[i] = debut du mot i ; bornes[n] = fin du dernier mot aligne
    bornes = [0.0] * (n + 1)
    dernier_connu = 0.0
    for i in range(n):
        bornes[i] = debuts[i] if debuts[i] is not None else dernier_connu
        if debuts[i] is not None:
            dernier_connu = debuts[i]
    bornes[n] = fins[n - 1] if fins[n - 1] is not None else dernier_connu
    # monotonie stricte : un span mal aligne ne doit jamais faire reculer le temps
    for i in range(1, n + 1):
        if bornes[i] < bornes[i - 1]:
            bornes[i] = bornes[i - 1]
    return bornes


def decouper_un_clip(pcm, sr, mots, bornes, dmin, dmax, rng,
                     p_troncature=0.6, max_essais=6):
    n = len(mots)
    if n < 1:
        return None
    for _ in range(max_essais):
        cible = rng.uniform(dmin, dmax)
        i = rng.randrange(n)
        j = i
        while j < n and bornes[j + 1] - bornes[i] <= cible:
            j += 1
        d = bornes[j] - bornes[i]
        if not (dmin <= d <= dmax and j > i):
            continue
        a = int(bornes[i] * sr)
        b_propre = min(int(bornes[j] * sr), len(pcm))
        tronque = False
        b = b_propre
        if j < n and rng.random() < p_troncature:
            duree_mot_suivant = bornes[j + 1] - bornes[j]
            fraction = rng.uniform(0.15, 0.85)
            b_essai = b_propre + int(duree_mot_suivant * fraction * sr)
            b_essai = min(b_essai, len(pcm))
            if b_essai > b_propre and (b_essai - a) / sr <= dmax + 2.0:
                b = b_essai
                tronque = True
        if b - a < int(0.5 * sr):
            continue
        return pcm[a:b], " ".join(mots[i:j]), tronque
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--nemo", default=str(
        BASE / "models" / "fastconformer-verifie-v1" / "causal-final.nemo"))
    ap.add_argument("--dmin", type=float, default=3.0)
    ap.add_argument("--dmax", type=float, default=8.0)
    ap.add_argument("--par_clip", type=int, default=2)
    ap.add_argument("--p_troncature", type=float, default=0.6)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--limite", type=int, default=None)
    ap.add_argument("--verifier_seulement", action="store_true",
                     help="ne rien ecrire, juste rendre les spans pour verif")
    a = ap.parse_args()

    import nemo.collections.asr as nemo_asr
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"chargement du modele sur {dev} : {a.nemo}", flush=True)
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(a.nemo, map_location=dev)
    model.eval()
    model.preprocessor.featurizer.dither = 0.0
    sp = model.tokenizer.tokenizer
    frame_sec = 0.08  # subsampling 8 x hop 10ms, meme convention que Horloge.MS_PAR_FRAME

    lignes = [json.loads(l) for l in open(TRAIN_MANIFEST, encoding="utf-8")]
    longs = [l for l in lignes if "train_wav_local" in l.get("audio_filepath", "")
             and not est_exclu(l["audio_filepath"])]
    if a.limite:
        longs = longs[:a.limite]
    print(f"{len(longs)} clips longs verifies (recitateurs contamines deja ecartes)", flush=True)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    rng = random.Random(a.seed)
    ecrits = tronques = non_alignes = trop_courts = 0

    fout = None if a.verifier_seulement else open(OUT_MANIFEST, "w", encoding="utf-8")
    with torch.no_grad():
        for k, l in enumerate(longs):
            mots = [w for w in l["text"].split() if est_un_mot(w)]
            if not mots:
                continue
            try:
                pcm = lire_wav16(l["audio_filepath"])
            except Exception:
                continue
            sig = torch.tensor(pcm, device=dev).unsqueeze(0)
            ln = torch.tensor([len(pcm)], device=dev)
            feats, flen = model.preprocessor(input_signal=sig, length=ln)
            enc, _ = model.encoder(audio_signal=feats, length=flen)
            lg = model.ctc_decoder(encoder_output=enc)
            lp = torch.log_softmax(lg, dim=-1)[0].cpu().numpy()

            spans = spans_mots(sp, lp, mots)
            if spans is None:
                non_alignes += 1
                continue
            blank_id = lp.shape[1] - 1
            bornes_frames = frontieres_par_blanc(lp, spans, blank_id)
            if bornes_frames is None:
                non_alignes += 1
                continue
            bornes = [b * frame_sec for b in bornes_frames]

            if a.verifier_seulement:
                yield_ = (l, mots, bornes, pcm)
                print(json.dumps({"verse_key": l.get("audio_filepath", ""),
                                  "mots": mots, "bornes": [round(b, 2) for b in bornes]},
                                 ensure_ascii=False))
                if k + 1 >= (a.limite or 10):
                    break
                continue

            for _ in range(a.par_clip):
                r = decouper_un_clip(pcm, 16000, mots, bornes, a.dmin, a.dmax, rng,
                                     p_troncature=a.p_troncature)
                if r is None:
                    trop_courts += 1
                    continue
                audio, texte, tronque = r
                if not texte:
                    trop_courts += 1
                    continue
                import soundfile as sf
                nom = f"court_{ecrits:06d}.wav"
                sf.write(str(OUT_DIR / nom), audio, 16000)
                fout.write(json.dumps({
                    "audio_filepath": str(OUT_DIR / nom),
                    "duration": round(len(audio) / 16000, 3),
                    "text": texte, "tronque": tronque,
                    "source": l["audio_filepath"],
                }, ensure_ascii=False) + "\n")
                ecrits += 1
                if tronque:
                    tronques += 1

            if (k + 1) % 2000 == 0:
                print(f"  {k+1}/{len(longs)}  ecrits={ecrits}", flush=True)

    if fout:
        fout.close()
        print(f"\n{ecrits} fragments ecrits -> {OUT_MANIFEST}")
        print(f"  dont tronques : {tronques} ({100*tronques/max(1,ecrits):.0f} %)")
        print(f"non alignes (span vide/Viterbi echoue) : {non_alignes}")
        print(f"aucune fenetre trouvee : {trop_courts}")


if __name__ == "__main__":
    main()
