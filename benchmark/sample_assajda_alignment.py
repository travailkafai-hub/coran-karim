"""Quantifie le desalignement des clips _assajda (batch2) sur un echantillon.
Juge: whisper-small-ft (WER 14.85%, valide). Un clip WER>0.5 = suspect.
Sortie: stats par reciteur + globales, logs/assajda_sample_scores.jsonl
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
import truststore; truststore.inject_into_ssl()
import json, re, sys
import numpy as np, soundfile as sf, torch
from pathlib import Path
from collections import defaultdict
from transformers import WhisperProcessor, WhisperForConditionalGeneration
from jiwer import wer as compute_wer

ROOT = Path(__file__).parent
N_SAMPLE = 800
THRESH = 0.5

_HAR = re.compile(r'[ً-ٰٟۖ-ۜ۟-ۭـ]')
def norm(t):
    t = _HAR.sub('', t)
    t = t.replace('أ','ا').replace('إ','ا').replace('آ','ا')
    t = t.replace('ى','ي').replace('ؤ','و').replace('ئ','ي')
    return re.sub(r'\s+', ' ', re.sub(r'[^؀-ۿ\s]','', t)).strip()

rows = []
for l in open(ROOT/"data"/"manifest_unified.jsonl", encoding="utf-8"):
    e = json.loads(l)
    if "_assajda" in e.get("reciter",""):
        rows.append(e)
print(f"{len(rows)} clips _assajda au total", flush=True)

rng = np.random.default_rng(42)
idx = rng.choice(len(rows), min(N_SAMPLE, len(rows)), replace=False)
sample = [rows[i] for i in idx]

proc = WhisperProcessor.from_pretrained("models/whisper-small-ft", language="arabic", task="transcribe")
model = WhisperForConditionalGeneration.from_pretrained("models/whisper-small-ft").to("cuda").eval()

out_f = open(ROOT/"logs"/"assajda_sample_scores.jsonl", "w", encoding="utf-8")
by_reciter = defaultdict(lambda: [0,0])  # [total, bad]
n_bad = 0
with torch.no_grad():
    for i, r in enumerate(sample):
        wav = Path(r["wav"])
        if not wav.exists():
            continue
        try:
            audio, sr = sf.read(str(wav), dtype="float32")
            feats = proc.feature_extractor(audio, sampling_rate=16000,
                                           return_tensors="pt").input_features.to("cuda")
            ids = model.generate(feats, language="arabic", task="transcribe",
                                 max_new_tokens=200)
            hyp = proc.tokenizer.decode(ids[0], skip_special_tokens=True).strip()
            w = compute_wer(norm(r["text"]), norm(hyp))
        except Exception as ex:
            print(f"  ERREUR {wav}: {ex}", flush=True)
            continue
        bad = w > THRESH
        by_reciter[r["reciter"]][0] += 1
        if bad:
            by_reciter[r["reciter"]][1] += 1
            n_bad += 1
        out_f.write(json.dumps({"key": r["key"], "reciter": r["reciter"],
                                "wer": round(w,3), "bad": bad}, ensure_ascii=False) + "\n")
        if (i+1) % 50 == 0:
            print(f"  {i+1}/{len(sample)} — suspects: {n_bad}", flush=True)
out_f.close()

print(f"\n=== RESULTAT ECHANTILLON ({len(sample)} clips, seuil WER>{THRESH}) ===", flush=True)
print(f"Suspects: {n_bad} ({100*n_bad/max(1,len(sample)):.1f}%)", flush=True)
print("\nPar reciteur (total / suspects):", flush=True)
for rec, (tot, bad) in sorted(by_reciter.items(), key=lambda x: -x[1][1]/max(1,x[1][0])):
    print(f"  {rec:35s} {tot:4d} / {bad:3d}  ({100*bad/max(1,tot):.0f}%)", flush=True)
print("DONE", flush=True)
