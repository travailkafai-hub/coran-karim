"""Test WhisperX sur des recitateurs SANS horodatage API -- ceux que
v4/generer_et_nettoyer_clips_courts.py ne peut pas couvrir (44 sur 54).

Objectif : verifier si WhisperX etend la couverture fiable au-dela des 10
recitateurs API-verifies, avant de l'integrer au pipeline de generation.
"""
import json
import random
import re
import sys
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
import whisperx

sys.path.insert(0, "/media/kafai/NouveauNom/Coran Karim/benchmark")
from generer_clips_courts_v4 import RECITATEURS as RECITATEURS_API

BASE = Path("/media/kafai/NouveauNom/Coran Karim/benchmark")
TRAIN_MANIFEST = BASE / "nemo_manifests_dual" / "train_manifest.jsonl"

_LETTRE_AR = re.compile(r"[ء-يٮ-ۓ]")


def est_un_mot(t):
    return bool(_LETTRE_AR.search(t))


def wer(ref, hyp):
    r, h = ref.split(), hyp.split()
    d = [[0] * (len(h) + 1) for _ in range(len(r) + 1)]
    for i in range(len(r) + 1):
        d[i][0] = i
    for j in range(len(h) + 1):
        d[0][j] = j
    for i in range(1, len(r) + 1):
        for j in range(1, len(h) + 1):
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1,
                          d[i - 1][j - 1] + (r[i - 1] != h[j - 1]))
    return d[-1][-1], len(r)


def norm(s):
    out = []
    for c in s:
        o = ord(c)
        if 0x064B <= o <= 0x0652 or o in (0x0670, 0x0640, 0x06DF, 0x06E0):
            continue
        if 0xE000 <= o <= 0xF8FF:
            continue
        if c in "أإآٱ":
            c = "ا"
        if c == "ى":
            c = "ي"
        out.append(c)
    return "".join(out)


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
    device = "cuda" if torch.cuda.is_available() else "cpu"
    model_a, metadata = whisperx.load_align_model(language_code="ar", device=device)
    print("modele d'alignement WhisperX charge", flush=True)

    import onnxruntime as ort
    from mel_numpy_reference import compute_mel_features
    vocab = json.loads((BASE / "models" / "contrastif-v1-eval" / "vocab.json")
                       .read_text(encoding="utf-8"))
    sess = ort.InferenceSession(str(BASE / "models" / "contrastif-v1-eval" / "model.onnx"),
                                providers=["CPUExecutionProvider"])

    def decoder(pcm):
        mel = compute_mel_features(pcm).astype(np.float32)
        lp = sess.run(None, {"audio_signal": mel[None],
                             "length": np.array([mel.shape[1]], dtype=np.int64)})[0][0]
        ids = lp.argmax(-1)
        out, prev = [], -1
        for t in ids:
            if t != prev and t < len(vocab):
                out.append(vocab[t])
            prev = t
        return "".join(out).replace("▁", " ").strip()

    lignes = [json.loads(l) for l in open(TRAIN_MANIFEST, encoding="utf-8")]
    longs = [l for l in lignes if "train_wav_local" in l.get("audio_filepath", "")]
    sans_api = [l for l in longs
                if not any(f"train_wav_local/{r}/" in l["audio_filepath"]
                           for r in RECITATEURS_API)]
    print(f"{len(sans_api)} clips SANS horodatage API disponibles", flush=True)

    rng = random.Random(7)
    echantillon = rng.sample(sans_api, min(300, len(sans_api)))

    gardes = generes = erreurs_align = 0
    wers = []
    for l in echantillon:
        try:
            pcm, sr = sf.read(l["audio_filepath"], dtype="float32")
            if sr != 16000:
                continue
        except Exception:
            continue
        mots = [w for w in l["text"].split() if est_un_mot(w)]
        if not mots:
            continue
        texte = " ".join(mots)
        segments = [{"text": texte, "start": 0.0, "end": len(pcm) / 16000}]
        try:
            result = whisperx.align(segments, model_a, metadata, pcm, device,
                                    return_char_alignments=False)
        except Exception:
            erreurs_align += 1
            continue
        mots_alignes = [w for seg in result["segments"] for w in seg.get("words", [])]
        if len(mots_alignes) != len(mots) or any("start" not in w for w in mots_alignes):
            erreurs_align += 1
            continue
        bornes = [mots_alignes[0]["start"]] + [w["end"] for w in mots_alignes]

        r = decouper_un_clip(pcm, 16000, mots, bornes, 3.0, 8.0, rng)
        if r is None:
            continue
        audio, cible_texte, tronque = r
        generes += 1
        hyp = norm(decoder(audio))
        ref = norm(cible_texte)
        e, n = wer(ref, hyp)
        if n == 0:
            continue
        w = e / n
        wers.append(w)
        if w <= 0.30:
            gardes += 1

    print(f"\n{len(echantillon)} clips testes, {generes} fragments generes")
    print(f"erreurs d'alignement (compte de mots incoherent) : {erreurs_align}")
    print(f"gardes (WER <= 30%) : {gardes}/{generes} ({100*gardes/max(1,generes):.0f} %)")
    print(f"WER median : {100*np.median(wers):.1f} %  |  WER moyen : {100*np.mean(wers):.1f} %")


if __name__ == "__main__":
    main()
