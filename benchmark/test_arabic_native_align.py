"""Test alignement force avec wav2vec2 arabe natif (harakat inclus, sans romanisation)."""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
import sys
sys.stdout.reconfigure(encoding="utf-8")
import truststore; truststore.inject_into_ssl()

import torch, torchaudio, soundfile as sf

MODEL = "jonatasgrosman/wav2vec2-large-xlsr-53-arabic"
WAV = "device_wavs/rec_last.wav"
REF_TEXT = "بِسْمِ اللَّهِ الرَّحْمَـٰنِ الرَّحِيمِ"

from transformers import AutoProcessor, AutoModelForCTC
print("Chargement modele...", flush=True)
proc = AutoProcessor.from_pretrained(MODEL)
model = AutoModelForCTC.from_pretrained(MODEL)
model.eval()

vocab = proc.tokenizer.get_vocab()
words = REF_TEXT.split()

def to_ids(s):
    ids = []
    for c in s:
        if c in vocab:
            ids.append(vocab[c])
    return ids

token_ids, word_spans = [], []
pos = 0
for w in words:
    ids = to_ids(w)
    word_spans.append((pos, pos + len(ids)))
    token_ids.extend(ids)
    pos += len(ids)

missing = [c for w in words for c in w if c not in vocab]
print("Caracteres hors-vocab (ignores):", set(missing), flush=True)
print(f"{len(token_ids)} tokens", flush=True)

data, sr = sf.read(WAV, dtype="float32")
if data.ndim > 1:
    data = data.mean(axis=1)
wav = torch.from_numpy(data).unsqueeze(0)
if sr != 16000:
    wav = torchaudio.functional.resample(wav, sr, 16000)

with torch.no_grad():
    inputs = proc(wav.squeeze().numpy(), sampling_rate=16000, return_tensors="pt")
    logits = model(inputs.input_values).logits
    log_probs = torch.log_softmax(logits, dim=-1)
print(f"emissions: {log_probs.shape}", flush=True)

targets = torch.tensor([token_ids], dtype=torch.int64)
input_lengths = torch.tensor([log_probs.shape[1]])
target_lengths = torch.tensor([len(token_ids)])
aligned_tokens, scores = torchaudio.functional.forced_align(
    log_probs, targets, input_lengths, target_lengths, blank=0,
)
aligned_tokens = aligned_tokens[0].tolist()

audio_dur_s = wav.shape[1] / 16000
n_frames = log_probs.shape[1]
frame_dur_s = audio_dur_s / n_frames
print(f"duree: {audio_dur_s:.2f}s, frames: {n_frames}, frame_dur: {frame_dur_s*1000:.1f}ms", flush=True)

search_from = 0
frame_for_token = []
for t in token_ids:
    found = None
    for f in range(search_from, len(aligned_tokens)):
        if aligned_tokens[f] == t:
            found = f
            search_from = f
            break
    frame_for_token.append(found)

for (start, end), w in zip(word_spans, words):
    fs = [f for f in frame_for_token[start:end] if f is not None]
    if fs:
        t0, t1 = min(fs) * frame_dur_s, max(fs) * frame_dur_s
        print(f"  {w:18s} : {t0:.2f}s -> {t1:.2f}s", flush=True)
    else:
        print(f"  {w:18s} : NON ALIGNE", flush=True)

print("OK", flush=True)
