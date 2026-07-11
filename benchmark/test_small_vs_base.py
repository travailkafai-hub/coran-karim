"""
Compare Whisper Small fine-tune (models/whisper-small-ft) vs base (openai/whisper-small)
sur des clips de test (voix inconnues). Tourne sur CPU pour ne pas gener le GPU.

Affiche : WER brut + WER normalise (sans harakat) + exemples cote a cote.
"""
import truststore; truststore.inject_into_ssl()
import os, json, re, time
os.environ.setdefault("HF_HOME", os.path.join(os.path.dirname(__file__), ".hf"))
import numpy as np, soundfile as sf, torch
from jiwer import wer as compute_wer
from transformers import WhisperProcessor, WhisperForConditionalGeneration

ROOT = os.path.dirname(os.path.abspath(__file__))
BASE = "openai/whisper-small"
FT   = os.path.join(ROOT, "models", "whisper-small-ft")
TEST = os.path.join(ROOT, "data", "test_voice_full.jsonl")
N    = 15
DEVICE = "cpu"   # GPU occupe par Medium

_HARAKAT = re.compile(r'[ً-ٰٟۖ-ۜ۟-ۭـ]')
def strip_harakat(t):
    return re.sub(r'\s+', ' ', _HARAKAT.sub('', t)).strip()

def load_clips(n):
    rows = [json.loads(l) for l in open(TEST, encoding="utf-8")]
    rows = [r for r in rows if os.path.exists(os.path.join(ROOT, r["wav"]))]
    rng = np.random.default_rng(0)
    idx = rng.choice(len(rows), min(n, len(rows)), replace=False)
    return [rows[i] for i in idx]

def transcribe_all(model_dir, clips, label):
    print(f"\nChargement {label} ({model_dir})...", flush=True)
    proc = WhisperProcessor.from_pretrained(model_dir, language="arabic", task="transcribe")
    model = WhisperForConditionalGeneration.from_pretrained(model_dir).to(DEVICE).eval()
    forced = proc.get_decoder_prompt_ids(language="arabic", task="transcribe")
    try:
        model.generation_config.is_multilingual = True
        model.generation_config.forced_decoder_ids = forced
        model.generation_config.suppress_tokens = []
    except Exception:
        pass
    hyps = []
    t0 = time.time()
    with torch.no_grad():
        for i, r in enumerate(clips):
            audio, _ = sf.read(os.path.join(ROOT, r["wav"]), dtype="float32")
            feats = proc.feature_extractor(audio, sampling_rate=16000,
                                           return_tensors="pt").input_features.to(DEVICE)
            ids = model.generate(feats, max_new_tokens=200)
            hyps.append(proc.tokenizer.decode(ids[0], skip_special_tokens=True).strip())
            print(f"  {label}: {i+1}/{len(clips)}", flush=True)
    print(f"  {label} fini en {time.time()-t0:.0f}s", flush=True)
    del model
    return hyps

def main():
    clips = load_clips(N)
    refs = [r["text"].strip() for r in clips]
    print(f"Test sur {len(clips)} clips (voix inconnues), CPU", flush=True)

    base_hyps = transcribe_all(BASE, clips, "BASE")
    ft_hyps   = transcribe_all(FT,   clips, "FT")

    wer_base = compute_wer(refs, base_hyps)
    wer_ft   = compute_wer(refs, ft_hyps)
    refs_n   = [strip_harakat(r) for r in refs]
    wer_base_n = compute_wer(refs_n, [strip_harakat(h) for h in base_hyps])
    wer_ft_n   = compute_wer(refs_n, [strip_harakat(h) for h in ft_hyps])

    print("\n" + "="*60)
    print("RESULTATS")
    print("="*60)
    print(f"{'':20} {'WER brut':>12} {'WER sans harakat':>18}")
    print(f"{'BASE (openai)':20} {wer_base:>11.1%} {wer_base_n:>17.1%}")
    print(f"{'FINE-TUNE (notre)':20} {wer_ft:>11.1%} {wer_ft_n:>17.1%}")
    gain = (wer_base - wer_ft) / max(wer_base, 1e-9) * 100
    print(f"\nGain fine-tune : {gain:.0f}% de reduction d'erreur (brut)")

    print("\n--- 4 exemples ---")
    for i in range(min(4, len(clips))):
        print(f"\n[{clips[i]['key']}]")
        print(f"  REF : {refs[i][:70]}")
        print(f"  BASE: {base_hyps[i][:70]}")
        print(f"  FT  : {ft_hyps[i][:70]}")
    print("\nTEST DONE", flush=True)

if __name__ == "__main__":
    main()
