"""Test alignement force MMS-300M sur un clip Coran reel.
Verifie si le timing mot-par-mot est exploitable pour le karaoke,
independamment de la justesse (harakat) qui reste le job de whisper-medium-ft.
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
import sys
sys.stdout.reconfigure(encoding="utf-8")
import truststore; truststore.inject_into_ssl()

import torch, torchaudio, uroman, soundfile as sf, numpy as np
from transformers import AutoProcessor, AutoModelForCTC

MODEL = "MahmoudAshraf/mms-300m-1130-forced-aligner"
WAV = "device_wavs/rec_last.wav"  # "Bismillah..." 5.6s, deja utilise pour les tests whisper
REF_TEXT = "بِسْمِ اللَّهِ الرَّحْمَـٰنِ الرَّحِيمِ"

print("Chargement modele MMS-300M...", flush=True)
proc = AutoProcessor.from_pretrained(MODEL)
model = AutoModelForCTC.from_pretrained(MODEL)
model.eval()

# 1. Romanisation du texte de reference (mot par mot, pour garder les frontieres)
u = uroman.Uroman()
words = REF_TEXT.split()
roman_words = [u.romanize_string(w).strip() for w in words]
print("Mots (arabe -> roman):", flush=True)
for w, r in zip(words, roman_words):
    print(f"  {w} -> {r}", flush=True)

vocab = proc.tokenizer.get_vocab()
def to_ids(s):
    return [vocab[c] for c in s.lower() if c in vocab]

# Sequence de tokens = concat des mots avec un separateur "|" implicite (espace)
# On garde les offsets de debut de chaque mot dans la sequence de tokens.
full_roman = " ".join(roman_words)
token_ids = []
word_token_spans = []  # (start, end) index dans token_ids pour chaque mot
pos = 0
for rw in roman_words:
    ids = to_ids(rw)
    start = pos
    token_ids.extend(ids)
    pos += len(ids)
    word_token_spans.append((start, pos))
    # espace = blank implicite entre mots, pas un token dedie ici

print(f"\n{len(token_ids)} tokens au total", flush=True)

# 2. Audio -> emissions (log-probs CTC)
data, sr = sf.read(WAV, dtype="float32")
if data.ndim > 1:
    data = data.mean(axis=1)
wav = torch.from_numpy(data).unsqueeze(0)
if sr != 16000:
    wav = torchaudio.functional.resample(wav, sr, 16000)

with torch.no_grad():
    inputs = proc(wav.squeeze().numpy(), sampling_rate=16000, return_tensors="pt")
    logits = model(inputs.input_values).logits  # (1, T, V)
    log_probs = torch.log_softmax(logits, dim=-1)

print(f"emissions shape: {log_probs.shape} (T frames)", flush=True)

# 3. Forced alignment (torchaudio officiel)
targets = torch.tensor([token_ids], dtype=torch.int64)
input_lengths = torch.tensor([log_probs.shape[1]])
target_lengths = torch.tensor([len(token_ids)])

aligned_tokens, scores = torchaudio.functional.forced_align(
    log_probs, targets, input_lengths, target_lengths, blank=0,
)
aligned_tokens = aligned_tokens[0].tolist()
scores = scores[0].tolist()

# 4. Frame -> temps (stride du modele wav2vec2/MMS = 20ms typique, a verifier via ratio)
audio_dur_s = wav.shape[1] / 16000
n_frames = log_probs.shape[1]
frame_dur_s = audio_dur_s / n_frames
print(f"\nDuree audio: {audio_dur_s:.2f}s, frames: {n_frames}, frame_dur: {frame_dur_s*1000:.1f}ms", flush=True)

# Reconstruire les timestamps de debut/fin par mot a partir des indices de frames
# ou chaque token de ce mot a ete "emis" (aligned_tokens contient l'id du token a
# chaque frame, avec repetitions -> on prend le premier et dernier frame ou le
# token du mot apparait dans l'ordre attendu).
frame_idx = 0
word_times = []
tok_ptr = 0
frame_for_token = [None] * len(token_ids)
for f, tok in enumerate(aligned_tokens):
    if tok != 0 and tok_ptr < len(token_ids) and tok == token_ids[tok_ptr]:
        if frame_for_token[tok_ptr] is None:
            frame_for_token[tok_ptr] = f
        # avancer seulement si la frame suivante n'est plus ce token (fin de la repetition)
    # approche simplifiee : on scanne apres coup

# Approche plus robuste : pour chaque token cible dans l'ordre, trouver la 1ere
# frame (>= position precedente) ou aligned_tokens correspond a ce token.
search_from = 0
frame_for_token = []
for t in token_ids:
    found = None
    for f in range(search_from, len(aligned_tokens)):
        if aligned_tokens[f] == t:
            found = f
            search_from = f  # ne pas reculer
            break
    frame_for_token.append(found)

for (start, end), w in zip(word_token_spans, words):
    fs = [f for f in frame_for_token[start:end] if f is not None]
    if fs:
        t0, t1 = min(fs) * frame_dur_s, max(fs) * frame_dur_s
        print(f"  {w:15s} : {t0:.2f}s -> {t1:.2f}s", flush=True)
    else:
        print(f"  {w:15s} : NON ALIGNE", flush=True)

print("\nOK", flush=True)
