"""
Audit qualite des alignements YouTube.
Re-transcrit un echantillon de clips YouTube avec Small (CPU) et compare au label.
Fort desaccord = alignement audio<->texte douteux.

GPU non utilise (CUDA_VISIBLE_DEVICES vide) -> Medium intact.
"""
import os
os.environ["CUDA_VISIBLE_DEVICES"] = ""
import truststore; truststore.inject_into_ssl()
os.environ.setdefault("HF_HOME", os.path.join(os.path.dirname(__file__), ".hf"))
import json, re, sys
import numpy as np, soundfile as sf, torch
from jiwer import wer as compute_wer
from transformers import WhisperProcessor, WhisperForConditionalGeneration

ROOT = os.path.dirname(os.path.abspath(__file__))
FT   = os.path.join(ROOT, "models", "whisper-small-ft")
MAN  = os.path.join(ROOT, "data", "manifest_youtube_aligned.jsonl")
N    = int(sys.argv[1]) if len(sys.argv) > 1 else 150

_HAR = re.compile(r'[ً-ٰٟۖ-ۜ۟-ۭـ]')
def norm(t):
    t = _HAR.sub('', t)
    t = t.replace('أ','ا').replace('إ','ا').replace('آ','ا').replace('ى','ي').replace('ؤ','و').replace('ئ','ي')
    return re.sub(r'\s+',' ', re.sub(r'[^؀-ۿ\s]','',t)).strip()

rows = [json.loads(l) for l in open(MAN, encoding="utf-8")]
rng = np.random.default_rng(0)
idx = rng.choice(len(rows), min(N, len(rows)), replace=False)
sample = [rows[i] for i in idx]
print(f"Audit de {len(sample)} clips YouTube (sur {len(rows)} total)", flush=True)

print("Chargement Small (CPU)...", flush=True)
proc = WhisperProcessor.from_pretrained(FT, language="arabic", task="transcribe")
model = WhisperForConditionalGeneration.from_pretrained(FT).to("cpu").eval()
try:
    model.generation_config.is_multilingual = True
    model.generation_config.forced_decoder_ids = proc.get_decoder_prompt_ids(language="arabic", task="transcribe")
    model.generation_config.suppress_tokens = []
except Exception: pass

good = med = bad = 0
bad_examples = []
with torch.no_grad():
    for i, r in enumerate(sample):
        p = os.path.join(ROOT, r["wav"])
        if not os.path.exists(p): continue
        audio, _ = sf.read(p, dtype="float32")
        feats = proc.feature_extractor(audio, sampling_rate=16000, return_tensors="pt").input_features
        ids = model.generate(feats, max_new_tokens=200)
        hyp = proc.tokenizer.decode(ids[0], skip_special_tokens=True).strip()
        w = compute_wer(norm(r["text"]), norm(hyp)) if norm(r["text"]) else 1.0
        if w < 0.3:   good += 1
        elif w < 0.7: med += 1
        else:
            bad += 1
            if len(bad_examples) < 5:
                bad_examples.append((r["key"], r["text"][:60], hyp[:60], round(w,2)))
        if (i+1) % 25 == 0:
            print(f"  {i+1}/{len(sample)} traites...", flush=True)

tot = good + med + bad
print(f"\n===== RESULTAT AUDIT (WER Small vs label, harakat ignore) =====", flush=True)
print(f"  BON      (WER<30%)   : {good}/{tot}  ({good/tot*100:.0f}%)  <- bien aligne", flush=True)
print(f"  MOYEN    (30-70%)    : {med}/{tot}  ({med/tot*100:.0f}%)  <- variations reciteur", flush=True)
print(f"  DOUTEUX  (WER>70%)   : {bad}/{tot}  ({bad/tot*100:.0f}%)  <- alignement suspect", flush=True)
print(f"\nExemples douteux (label vs ce que Small entend):", flush=True)
for k, ref, hyp, w in bad_examples:
    print(f"  [{k}] WER={w}", flush=True)
    print(f"    label: {ref}", flush=True)
    print(f"    Small: {hyp}", flush=True)
print("AUDIT DONE", flush=True)
