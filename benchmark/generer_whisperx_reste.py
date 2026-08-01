#!/usr/bin/env python3
"""GENERE le corpus 3-8s pour les 44 recitateurs SANS horodatage API, via
alignement WhisperX (wav2vec2-large-xlsr-53-arabic) + FILTRE QUALITE par
decodage (meme principe que generer_et_nettoyer_clips_courts.py).

Complement de v4 (10 recitateurs API-verifies) : etend la couverture aux 44
recitateurs restants. Mesure sur echantillon (300 clips, 2026-08-01) :
44 % de survie au filtre WER<=30%, median 33,3% AVANT filtre -- comparable a
la meilleure methode maison (blanc, 33,9%), mais couvre des recitateurs
INACCESSIBLES avant. Le filtre post-generation absorbe l'imprecision residuelle.
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

BASE = Path("/media/kafai/NouveauNom/Coran Karim/benchmark")
sys.path.insert(0, str(BASE))
from generer_clips_courts_v4 import RECITATEURS as RECITATEURS_API  # noqa: E402
from mel_numpy_reference import compute_mel_features  # noqa: E402

TRAIN_MANIFEST = BASE / "nemo_manifests_dual" / "train_manifest.jsonl"
OUT_DIR = BASE / "data" / "clips_courts_whisperx"
OUT_MANIFEST = OUT_DIR / "manifest.jsonl"
SEUIL_WER = 0.30

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
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--dmin", type=float, default=3.0)
    ap.add_argument("--dmax", type=float, default=8.0)
    ap.add_argument("--par_clip", type=int, default=2)
    ap.add_argument("--p_troncature", type=float, default=0.6)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--limite", type=int, default=None)
    ap.add_argument("--seuil_wer", type=float, default=SEUIL_WER)
    a = ap.parse_args()

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model_a, metadata = whisperx.load_align_model(language_code="ar", device=device)
    print("modele WhisperX charge", flush=True)

    import onnxruntime as ort
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
    if a.limite:
        sans_api = sans_api[:a.limite]
    print(f"{len(sans_api)} clips sans horodatage API (44 recitateurs)", flush=True)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    rng = random.Random(a.seed)
    generes = gardes = rejetes_wer = erreurs_align = trop_courts = 0

    with open(OUT_MANIFEST, "w", encoding="utf-8") as fout:
        for k, l in enumerate(sans_api):
            try:
                pcm, sr = sf.read(l["audio_filepath"], dtype="float32")
                if sr != 16000:
                    continue
            except Exception:
                continue
            mots = [w for w in l["text"].split() if est_un_mot(w)]
            if not mots:
                continue
            texte_complet = " ".join(mots)
            segments = [{"text": texte_complet, "start": 0.0, "end": len(pcm) / 16000}]
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
                generes += 1
                hyp = norm(decoder(audio))
                ref = norm(texte)
                e, n = wer(ref, hyp)
                if n == 0 or e / n > a.seuil_wer:
                    rejetes_wer += 1
                    continue
                nom = f"court_{gardes:06d}.wav"
                sf.write(str(OUT_DIR / nom), audio, 16000)
                fout.write(json.dumps({
                    "audio_filepath": str(OUT_DIR / nom),
                    "duration": round(len(audio) / 16000, 3),
                    "text": texte, "tronque": tronque,
                    "source": l["audio_filepath"],
                }, ensure_ascii=False) + "\n")
                gardes += 1

            if (k + 1) % 1000 == 0:
                print(f"  {k+1}/{len(sans_api)}  generes={generes} gardes={gardes} "
                      f"({100*gardes/max(1,generes):.0f} %)  erreurs_align={erreurs_align}",
                      flush=True)

    print(f"\n{gardes} fragments GARDES sur {generes} generes "
          f"({100*gardes/max(1,generes):.0f} %) -> {OUT_MANIFEST}")
    print(f"rejetes WER > {a.seuil_wer:.0%} : {rejetes_wer}")
    print(f"erreurs d'alignement WhisperX : {erreurs_align}")
    print(f"aucune fenetre trouvee : {trop_courts}")


if __name__ == "__main__":
    main()
