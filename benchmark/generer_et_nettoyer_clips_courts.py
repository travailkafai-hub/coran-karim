#!/usr/bin/env python3
"""GENERE le corpus 3-8s (v4, horodatages API reels, 10 recitateurs fiables)
PUIS NETTOIE fragment par fragment avec le modele -- au lieu d'exiger que la
methode d'alignement soit parfaite partout, on decode CHAQUE fragment produit
et on NE GARDE que ceux ou le decode colle au texte assigne. Le reste est
jete, pas corrige, pas explique -- au fragment suivant.

Decision utilisateur (2026-08-01) apres 4 methodes d'alignement dont chacune
butait sur un exemple different : « tas un modele plutot fiable, lance sur
tout ce qu'on a besoin, fiabilise la dataset ; si un fragment ne colle pas tu
le supprimes et tu passes au suivant ». Le modele sert de FILTRE DE QUALITE
post-generation, pas de methode d'alignement -- il ne fait que confirmer ou
rejeter ce que v4 a produit avec les vrais horodatages.

Seuil : WER <= 30 % par fragment (norme -- harakat retirees, hamza unifiee).
Choisi sur la distribution mesuree : les fragments bien alignes se groupent
sous ~20 %, les mal alignes (decalage d'indexation autour d'une pause,
cf. PROBLEME_DECOUPE_CLIPS_COURTS.md) sautent a 100-600 %. Pas de zone grise
notable entre les deux.
"""
import json
import re
import sys
from pathlib import Path

import numpy as np
import soundfile as sf
import torch

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from generer_clips_courts_v4 import (   # noqa: E402
    RECITATEURS, est_un_mot, lire_wav16, charger_segments,
    bornes_depuis_segments, decouper_un_clip,
)

TRAIN_MANIFEST = BASE / "nemo_manifests_dual" / "train_manifest.jsonl"
OUT_DIR = BASE / "data" / "clips_courts_final"
OUT_MANIFEST = OUT_DIR / "manifest.jsonl"
SEUIL_WER = 0.30


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
    ap.add_argument("--nemo", default=str(
        BASE / "models" / "contrastif-v1-eval" / "model.onnx"),
        help="modele ONNX pour le filtre qualite (une seule tete, logprobs)")
    ap.add_argument("--vocab", default=str(
        BASE / "models" / "contrastif-v1-eval" / "vocab.json"))
    a = ap.parse_args()

    import onnxruntime as ort
    from nemo.collections.asr.modules import AudioToMelSpectrogramPreprocessor
    prep = AudioToMelSpectrogramPreprocessor(
        sample_rate=16000, features=80, n_fft=512,
        window_size=0.025, window_stride=0.01, normalize="per_feature")
    prep.eval()
    vocab = json.loads(Path(a.vocab).read_text(encoding="utf-8"))
    sess = ort.InferenceSession(a.nemo, providers=["CPUExecutionProvider"])

    def decoder(pcm):
        with torch.no_grad():
            mel, ml = prep(input_signal=torch.tensor(pcm).unsqueeze(0),
                           length=torch.tensor([len(pcm)]))
        lp = sess.run(None, {"audio_signal": mel.numpy(),
                             "length": ml.numpy().astype(np.int64)})[0][0]
        ids = lp.argmax(-1)
        out, prev = [], -1
        for t in ids:
            if t != prev and t < len(vocab):
                out.append(vocab[t])
            prev = t
        return "".join(out).replace("▁", " ").strip()

    lignes = [json.loads(l) for l in open(TRAIN_MANIFEST, encoding="utf-8")]
    longs = [l for l in lignes
             if any(f"train_wav_local/{r}/" in l.get("audio_filepath", "")
                    for r in RECITATEURS)]
    if a.limite:
        longs = longs[:a.limite]
    print(f"{len(longs)} clips sur {len(RECITATEURS)} recitateurs fiables", flush=True)

    import random
    rng = random.Random(a.seed)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    cache_mem = {}
    generes = gardes = rejetes_wer = decompte_diff = trop_courts = tronques_gardes = 0

    with open(OUT_MANIFEST, "w", encoding="utf-8") as fout:
        for k, l in enumerate(longs):
            p = Path(l["audio_filepath"])
            m = re.match(r"^(\d+)_(\d+)$", p.stem)
            if not m:
                continue
            surah, ayah = int(m.group(1)), int(m.group(2))
            reci = p.parent.name
            rid, cache_dir = RECITATEURS[reci]

            mots = [w for w in l["text"].split() if est_un_mot(w)]
            if not mots:
                continue
            seg = charger_segments(cache_dir, rid, surah, ayah, cache_mem)
            bornes = bornes_depuis_segments(seg, len(mots))
            if bornes is None:
                decompte_diff += 1
                continue

            pcm = lire_wav16(l["audio_filepath"])
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

                # ── FILTRE QUALITE : decoder et comparer, garder ou jeter ──
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
                    "source": l["audio_filepath"], "recitateur": reci,
                    "wer_filtre": round(e / n, 3),
                }, ensure_ascii=False) + "\n")
                gardes += 1
                if tronque:
                    tronques_gardes += 1

            if (k + 1) % 1000 == 0:
                print(f"  {k+1}/{len(longs)}  generes={generes} gardes={gardes} "
                      f"({100*gardes/max(1,generes):.0f} %)", flush=True)

    print(f"\n{gardes} fragments GARDES sur {generes} generes "
          f"({100*gardes/max(1,generes):.0f} %) -> {OUT_MANIFEST}")
    print(f"  dont tronques gardes : {tronques_gardes} ({100*tronques_gardes/max(1,gardes):.0f} %)")
    print(f"rejetes par le filtre qualite (WER > {a.seuil_wer:.0%}) : {rejetes_wer}")
    print(f"decompte de mots API != manifeste (ecarte avant meme decoupe) : {decompte_diff}")
    print(f"aucune fenetre trouvee : {trop_courts}")
    heures = sum(1 for _ in open(OUT_MANIFEST, encoding="utf-8"))
    print(f"\nfragments finaux : {heures}")


if __name__ == "__main__":
    main()
