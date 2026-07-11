"""QA par similarite CARACTERE (pas mot) via juge CTC.
Le CTC generique (non specialise Coran) fait des erreurs lettre-a-lettre
(hamza, alef) qui font compter un MOT entier comme faux en WER -> signal
trop bruite. La similarite caractere (1 - levenshtein/maxlen) reste haute
si le verset est le bon (malgre le bruit CTC), et s'effondre si le verset
est reellement different (contenu sans rapport).
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
import truststore; truststore.inject_into_ssl()
import sys, json, re, argparse
import numpy as np, soundfile as sf, torch
sys.stdout.reconfigure(encoding="utf-8")
from transformers import AutoProcessor, AutoModelForCTC

_HAR = re.compile(r'[ً-ٰٟؐ-ؚۖ-ۭـ]')
def norm(t):
    t = _HAR.sub('', t)
    t = t.replace('أ','ا').replace('إ','ا').replace('آ','ا').replace('ٱ','ا')
    t = t.replace('ى','ي').replace('ؤ','و').replace('ئ','ي').replace('ة','ه')
    return re.sub(r'\s+', ' ', re.sub(r'[^؀-ۿ]','', t)).strip()

def char_sim(a, b):
    a, b = norm(a), norm(b)
    if not a or not b: return 0.0
    m, n = len(a), len(b)
    dp = list(range(n+1))
    for i in range(1, m+1):
        prev, dp[0] = dp[0], i
        for j in range(1, n+1):
            tmp = dp[j]
            dp[j] = min(dp[j]+1, dp[j-1]+1, prev+(a[i-1]!=b[j-1]))
            prev = tmp
    return 1 - dp[n]/max(m,n)

ap = argparse.ArgumentParser()
ap.add_argument("--jsonl", required=True)
args = ap.parse_args()

proc = AutoProcessor.from_pretrained("jonatasgrosman/wav2vec2-large-xlsr-53-arabic")
model = AutoModelForCTC.from_pretrained("jonatasgrosman/wav2vec2-large-xlsr-53-arabic").to("cuda").eval()

rows = [json.loads(l) for l in open(args.jsonl, encoding="utf-8")]
print(f"{len(rows)} clips a juger (similarite caractere)", flush=True)
results = []
with torch.no_grad():
    for i, r in enumerate(rows):
        a, sr = sf.read(r["wav"], dtype="float32")
        if a.ndim > 1: a = a.mean(axis=1)
        x = proc(a, sampling_rate=sr, return_tensors="pt").input_values.to("cuda")
        logits = model(x).logits[0]
        ids = torch.argmax(logits, dim=-1)
        hyp = proc.tokenizer.decode(ids)
        sim = char_sim(r["text"], hyp)
        results.append((r["key"], sim, r.get("align_score", 0.0), hyp))
        if (i+1) % 50 == 0:
            print(f"  {i+1}/{len(rows)}", flush=True)

sims = np.array([s for _, s, _, _ in results])
print(f"\nclips QA: {len(sims)}", flush=True)
print(f"similarite mediane: {np.median(sims):.3f} | moyenne: {sims.mean():.3f}", flush=True)
for th in [0.5, 0.6, 0.7, 0.8]:
    print(f"  sim>={th}: {(sims>=th).mean()*100:.0f}%", flush=True)
print("\npires 12 (sim la plus basse = vrai desalignement probable):", flush=True)
for k, s, sc, h in sorted(results, key=lambda x: x[1])[:12]:
    print(f"  {k}: sim={s:.2f} align_score={sc:.2f}  hyp={h[:50]}", flush=True)
print("QA DONE", flush=True)
