"""Verifie que les 42 reciteurs de train_wav_local (source everyayah.com) sont
bien Hafs et non Warsh -- meme methode que celle deja utilisee et documentee
pour les 12 reciteurs _assajda (asr.md, "Contamination riwaya"), reappliquee
ici car ELLE N'AVAIT JAMAIS ETE FAITE sur ce groupe (question soulevee par
l'utilisateur le 2026-07-26 : "on a plus de 50 reciteurs").

METHODE : transcrire un verset ou Hafs et Warsh different AUDIBLEMENT (pas
juste une harakat) avec un modele CTC arabe NEUTRE (pas nos modeles Coran,
biaises vers le canonique Hafs -- ils "corrigeraient" du Warsh vers du Hafs
et masqueraient la contamination).
  3:146  Hafs "قَٰتَلَ" (qatala, alef long)  vs  Warsh "قُتِلَ" (qutila, sans alef)
  57:24  Hafs contient "هُوَ"                 vs  Warsh sans "هُوَ"
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
import glob
import re
import wave
from pathlib import Path

import torch
import numpy as np
from transformers import Wav2Vec2ForCTC, Wav2Vec2Processor

MODEL_ID = "jonatasgrosman/wav2vec2-large-xlsr-53-arabic"
BASE = Path(__file__).parent
SRC = BASE / "data" / "train_wav_local"

print(f"Chargement du modele NEUTRE : {MODEL_ID}")
proc = Wav2Vec2Processor.from_pretrained(MODEL_ID)
model = Wav2Vec2ForCTC.from_pretrained(MODEL_ID).eval()
if torch.cuda.is_available():
    try:
        model = model.cuda()
    except Exception:
        pass


def read_wav(path):
    with wave.open(str(path), "rb") as w:
        raw = w.readframes(w.getnframes())
        sr = w.getframerate()
    x = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    return x, sr


def transcribe(path):
    x, sr = read_wav(path)
    assert sr == 16000, f"{path}: {sr}Hz inattendu"
    inputs = proc(x, sampling_rate=16000, return_tensors="pt")
    with torch.no_grad():
        iv = inputs.input_values
        if torch.cuda.is_available():
            iv = iv.cuda()
        logits = model(iv).logits.cpu()
    ids = torch.argmax(logits, dim=-1)
    return proc.batch_decode(ids)[0]


def has_alef_madd(s):
    # قَٰتَلَ (Hafs) contient un alef long/madd apres le qaf ; قُتِلَ (Warsh) non.
    return bool(re.search(r"قات|قاتل|قتال", s)) 


reciters = sorted(d.name for d in SRC.iterdir() if d.is_dir())
print(f"{len(reciters)} dossiers reciteur a verifier\n")

print(f"{'reciteur':<45s} {'3:146':<30s} {'57:24':<30s}  verdict")
print("-" * 120)
suspect = []
for rec in reciters:
    d = SRC / rec
    c1 = list(d.glob("3_146.wav"))
    c2 = list(d.glob("57_24.wav"))
    t1 = transcribe(c1[0]) if c1 else None
    t2 = transcribe(c2[0]) if c2 else None
    v146 = "HAFS(qatala)" if t1 and has_alef_madd(t1) else ("WARSH?(qutila)" if t1 else "absent")
    v2427 = "HAFS(howa)" if t2 and "هو" in t2 else ("WARSH?(sans howa)" if t2 else "absent")
    flag = "?" in v146 + v2427
    if flag: suspect.append(rec)
    print(f"{rec:<45s} {(t1 or '(absent)')[:28]:<30s} {(t2 or '(absent)')[:28]:<30s}  "
          f"{'SUSPECT' if flag else 'OK'}")

print(f"\n{len(suspect)} reciteur(s) suspect(s) sur {len(reciters)} : {suspect}")
