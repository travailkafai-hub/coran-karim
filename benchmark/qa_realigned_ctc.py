"""QA des clips realignes via juge CTC (wav2vec2-arabe) plutot que Whisper.
Whisper (auto-regressif) hallucine sur les clips courts isoles sans contexte
(derive vers un autre passage du Coran) -> faux negatifs massifs en QA.
Le CTC (frame->phoneme direct, non generatif) ne peut pas "s'egarer" de la
meme facon -> juge nettement plus fiable pour valider un realignement.
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
import truststore; truststore.inject_into_ssl()
import sys, json, re, argparse
import numpy as np, soundfile as sf, torch
sys.stdout.reconfigure(encoding="utf-8")
from transformers import AutoProcessor, AutoModelForCTC
from jiwer import wer as compute_wer

_HAR = re.compile(r'[ً-ٰٟؐ-ؚۖ-ۭـ]')
def norm(t):
    t = _HAR.sub('', t)
    t = t.replace('أ','ا').replace('إ','ا').replace('آ','ا').replace('ٱ','ا')
    t = t.replace('ى','ي').replace('ؤ','و').replace('ئ','ي')
    return re.sub(r'\s+', ' ', re.sub(r'[^؀-ۿ\s]','', t)).strip()

ap = argparse.ArgumentParser()
ap.add_argument("--jsonl", required=True)
args = ap.parse_args()

proc = AutoProcessor.from_pretrained("jonatasgrosman/wav2vec2-large-xlsr-53-arabic")
model = AutoModelForCTC.from_pretrained("jonatasgrosman/wav2vec2-large-xlsr-53-arabic").to("cuda").eval()

rows = [json.loads(l) for l in open(args.jsonl, encoding="utf-8")]
print(f"{len(rows)} clips a juger (CTC)", flush=True)
wers = []
with torch.no_grad():
    for i, r in enumerate(rows):
        a, sr = sf.read(r["wav"], dtype="float32")
        if a.ndim > 1: a = a.mean(axis=1)
        x = proc(a, sampling_rate=sr, return_tensors="pt").input_values.to("cuda")
        logits = model(x).logits[0]
        ids = torch.argmax(logits, dim=-1)
        hyp = proc.tokenizer.decode(ids)
        w = compute_wer(norm(r["text"]), norm(hyp))
        wers.append((r["key"], w, r.get("align_score", 0.0)))
        if (i+1) % 50 == 0:
            print(f"  {i+1}/{len(rows)}", flush=True)

ws = np.array([w for _, w, _ in wers])
print(f"\nclips QA: {len(ws)}", flush=True)
print(f"WER mediane: {np.median(ws):.3f} | moyenne: {ws.mean():.3f}", flush=True)
for th in [0.3, 0.5, 0.7]:
    print(f"  WER<={th}: {(ws<=th).mean()*100:.0f}%", flush=True)
print("\npires 10 clips:", flush=True)
for k, w, sc in sorted(wers, key=lambda x: -x[1])[:10]:
    print(f"  {k}: WER={w:.2f} align_score={sc}", flush=True)
print("QA DONE", flush=True)
