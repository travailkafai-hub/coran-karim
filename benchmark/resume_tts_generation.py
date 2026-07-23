#!/usr/bin/env python3
"""
Resume TTS generation from index 18115 (last successful was 18114).
Generates only the missing ~52 clips (tts_18115 to tts_18166).
"""
import os, json, random
os.environ.setdefault("COQUI_TOS_AGREED", "1")
from pathlib import Path

BASE_DIR = Path(__file__).parent
os.environ.setdefault("TTS_HOME", str(BASE_DIR / "tts-cache"))
os.environ.setdefault("HF_HOME", str(BASE_DIR / "hf-cache"))

import torch

# PyTorch >=2.6 a bascule le defaut de torch.load vers weights_only=True, ce
# qui casse le chargement du checkpoint XTTS (classes de config pickled non
# whitelistees, ex. XttsConfig). Fichier local de confiance (deja telecharge
# depuis le repo officiel Coqui) -- on restaure l'ancien comportement.
_orig_load = torch.load
def _patched_load(*args, **kwargs):
    kwargs.setdefault("weights_only", False)
    return _orig_load(*args, **kwargs)
torch.load = _patched_load

# torchaudio >=2.11 a retire son ancien dispatch de backends (soundfile/sox)
# au profit de torchcodec, qui exige des libs natives NVIDIA (libnpp) non
# presentes ici. XTTS n'utilise torchaudio.load QUE pour charger le wav de
# reference du locuteur (TTS/tts/models/xtts.py:load_audio) -- on le
# remplace par une lecture soundfile directe (deja installe), meme
# signature de retour (tensor [canaux, echantillons], sample_rate).
import torchaudio
import soundfile as sf
import numpy as np

def _patched_torchaudio_load(path, *args, **kwargs):
    data, sr = sf.read(str(path), dtype="float32", always_2d=True)
    tensor = torch.from_numpy(np.ascontiguousarray(data.T))
    return tensor, sr

torchaudio.load = _patched_torchaudio_load

from TTS.api import TTS

# Import the original build functions from generate_tts_augmentation
import sys
sys.path.insert(0, str(BASE_DIR))
from generate_tts_augmentation import build_plan, VOICES, RECITER_REFS

OUT_DIR = BASE_DIR / "data" / "tts_augmentation"
OUT_MANIFEST = OUT_DIR / "manifest.jsonl"

RESUME_FROM_INDEX = 18115

def main():
    plan = build_plan(n_words=9500)  # Full plan ~18000+ items

    print(f"Plan total : {len(plan)} variantes")
    print(f"Reprenant depuis index {RESUME_FROM_INDEX} (clip tts_{RESUME_FROM_INDEX}.wav)")

    # Assign voices (same as original)
    random.seed(7)  # Same seed as original
    random.shuffle(plan)
    n_v = len(VOICES)
    chunk = (len(plan) + n_v - 1) // n_v
    voice_assignment = []
    for idx in range(len(plan)):
        voice_assignment.append(VOICES[min(idx // chunk, n_v - 1)])

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Chargement XTTS-v2 sur {device}...")
    tts = TTS("tts_models/multilingual/multi-dataset/xtts_v2").to(device)

    wav_dir = OUT_DIR / "wav"
    wav_dir.mkdir(exist_ok=True)

    done = 0
    with open(OUT_MANIFEST, "a", encoding="utf-8") as mf:
        for i in range(RESUME_FROM_INDEX, min(RESUME_FROM_INDEX + 100, len(plan))):
            correct, wrong, kind, detail = plan[i]
            v = voice_assignment[i]
            # Entrees NTFS/FUSE corrompues constatees sur cette plage precise
            # (18115-18166) : meme `rm` echoue dessus (I/O error persistant,
            # pas transitoire) -- probablement un reliquat d'une ecriture
            # interrompue lors de la tentative originale. On ne touche PAS au
            # systeme de fichiers (montage partage avec l'entrainement en
            # cours) -- on contourne en essayant un nom de fichier alternatif
            # des qu'une erreur I/O survient sur l'ecriture.
            clip_name = f"tts_{i}.wav"
            out_path = wav_dir / clip_name
            for suffix in ("", "_r", "_r2"):
                if suffix:
                    clip_name = f"tts_{i}{suffix}.wav"
                    out_path = wav_dir / clip_name
                try:
                    tts.tts_to_file(text=wrong, file_path=str(out_path),
                                    speaker_wav=str(RECITER_REFS[v]), language="ar")
                    break
                except Exception as e:
                    print(f"  [erreur] i={i} mot={wrong!r} voix={v} fichier={clip_name}: {e}")
            else:
                continue

            mf.write(json.dumps({
                "clip": clip_name, "text": wrong, "correct_text": correct,
                "kind": kind, "detail": detail, "voice": v,
            }, ensure_ascii=False) + "\n")
            mf.flush()

            done += 1
            if done % 10 == 0:
                print(f"  {i+1}/{RESUME_FROM_INDEX + done} — {done} clips complétés")

    print(f"\nTerminé : {done} clips manquants générés")

if __name__ == "__main__":
    main()
