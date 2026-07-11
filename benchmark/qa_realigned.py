"""QA WER des clips realignes d'un reciteur (juge whisper-small-ft, batch GPU)."""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
import truststore; truststore.inject_into_ssl()
import sys, json, re, argparse
import numpy as np, soundfile as sf, torch
sys.stdout.reconfigure(encoding="utf-8")
from transformers import WhisperProcessor, WhisperForConditionalGeneration
from jiwer import wer as compute_wer

_HAR = re.compile(r'[ً-ٰٟؐ-ؚۖ-ۭـ]')
def norm(t):
    t = _HAR.sub('', t)
    t = t.replace('أ','ا').replace('إ','ا').replace('آ','ا').replace('ٱ','ا')
    t = t.replace('ى','ي').replace('ؤ','و').replace('ئ','ي')
    return re.sub(r'\s+', ' ', re.sub(r'[^؀-ۿ\s]','', t)).strip()

ap = argparse.ArgumentParser()
ap.add_argument("--jsonl", required=True)
ap.add_argument("--batch", type=int, default=8)
args = ap.parse_args()

proc = WhisperProcessor.from_pretrained("models/whisper-small-ft", language="arabic", task="transcribe")
model = WhisperForConditionalGeneration.from_pretrained(
    "models/whisper-small-ft", dtype=torch.float16).to("cuda").eval()

rows = [json.loads(l) for l in open(args.jsonl, encoding="utf-8")]
print(f"{len(rows)} clips a juger", flush=True)
wers = []
with torch.no_grad():
    for i in range(0, len(rows), args.batch):
        batch = rows[i:i+args.batch]
        feats = []
        for r in batch:
            a, sr = sf.read(r["wav"], dtype="float32")
            if a.ndim > 1: a = a.mean(axis=1)
            if len(a) > 30*sr: a = a[:30*sr]
            feats.append(proc.feature_extractor(a, sampling_rate=16000).input_features[0])
        x = torch.tensor(np.stack(feats)).to("cuda", dtype=torch.float16)
        ids = model.generate(x, language="arabic", task="transcribe", max_new_tokens=200)
        for r, seq in zip(batch, ids):
            hyp = proc.tokenizer.decode(seq, skip_special_tokens=True).strip()
            w = compute_wer(norm(r["text"]), norm(hyp))
            wers.append((r["key"], w, r.get("align_score", 0.0)))
        if (i // args.batch) % 5 == 0:
            print(f"  {i+len(batch)}/{len(rows)}", flush=True)

ws = np.array([w for _, w, _ in wers])
print(f"\nclips QA: {len(ws)}", flush=True)
print(f"WER mediane: {np.median(ws):.3f} | moyenne: {ws.mean():.3f}", flush=True)
for th in [0.2, 0.3, 0.5]:
    print(f"  WER<={th}: {(ws<=th).mean()*100:.0f}%", flush=True)
print("\npires 8 clips:", flush=True)
for k, w, sc in sorted(wers, key=lambda x: -x[1])[:8]:
    print(f"  {k}: WER={w:.2f} align_score={sc}", flush=True)
# correlation align_score <-> WER (le score peut-il servir de filtre sans juge ?)
scs = np.array([s for _, _, s in wers])
if scs.std() > 0:
    bad = ws > 0.5
    print(f"\nalign_score moyen (bons): {scs[~bad].mean():.2f} | (mauvais): {scs[bad].mean() if bad.any() else float('nan'):.2f}", flush=True)
print("QA DONE", flush=True)
