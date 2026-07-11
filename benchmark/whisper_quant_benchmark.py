"""
Benchmark de quantification Whisper — 5 configurations déploiement mobile :

  Base  FT  Float32   296 MB  ← référence entraînement
  Base  FT  INT8       75 MB  ← mobile entrée de gamme
  Small FT  INT8      245 MB  ← meilleur qualité / taille
  Small FT  INT4      125 MB  ← compact haute qualité
  Medium FT INT4      385 MB  ← meilleure qualité absolue

Pour chaque configuration :
  - WER sur test_voice_full (200 clips, reciters inconnus)
  - WER sur test_text_full  (200 clips, versets inconnus)
  - Faux positif rate / recall
  - Taille estimée sur mobile (MB)
  - Latence moyenne par clip (s)

Usage:
  python whisper_quant_benchmark.py

Résultats → results/quant_benchmark.json + quant_benchmark.csv
"""
import truststore; truststore.inject_into_ssl()
import os, json, time, copy
import numpy as np
import soundfile as sf
import torch
import torch.nn as nn
from jiwer import wer as compute_wer
from transformers import WhisperProcessor, WhisperForConditionalGeneration

ROOT    = os.path.dirname(os.path.abspath(__file__))
RESULTS = os.path.join(ROOT, "results")
os.makedirs(RESULTS, exist_ok=True)

MODELS = {
    "base_ft":   os.path.join(ROOT, "models", "whisper-full-ft"),
    "small_ft":  os.path.join(ROOT, "models", "whisper-small-ft"),
    "medium_ft": os.path.join(ROOT, "models", "whisper-medium-ft"),
}

# Approximate on-disk size per format (MB) — used when model not yet trained
SIZE_ESTIMATES = {
    "base_ft":   {"float32": 296,  "int8": 75,  "int4": 40},
    "small_ft":  {"float32": 976,  "int8": 245, "int4": 125},
    "medium_ft": {"float32": 3070, "int8": 770, "int4": 385},
}

TEST_SETS = {
    "voice": os.path.join(ROOT, "data", "test_voice_full.jsonl"),
    "text":  os.path.join(ROOT, "data", "test_text_full.jsonl"),
}
N_SAMPLE = 200   # clips per test set


# ── Evaluation helpers ────────────────────────────────────────────────────────

def load_sample(manifest_path: str, n: int) -> list[dict]:
    rows = [json.loads(l) for l in open(manifest_path, encoding="utf-8")]
    rng  = np.random.default_rng(42)
    idx  = rng.choice(len(rows), min(n, len(rows)), replace=False)
    return [rows[i] for i in idx]


def run_eval(model, proc, rows: list[dict], label: str) -> dict:
    model.eval()
    device = next(model.parameters()).device
    refs, hyps = [], []
    latencies  = []
    errors_text, errors_voice = 0, 0

    with torch.no_grad():
        for r in rows:
            wav_path = os.path.join(ROOT, r["wav"])
            if not os.path.exists(wav_path):
                continue
            audio, _ = sf.read(wav_path, dtype="float32")
            feats = proc.feature_extractor(
                audio, sampling_rate=16000, return_tensors="pt"
            ).input_features.to(device)

            try:
                model.generation_config.is_multilingual = True
                model.generation_config.forced_decoder_ids = proc.get_decoder_prompt_ids(language="arabic", task="transcribe")
                model.generation_config.suppress_tokens = []
            except Exception:
                pass
            t0 = time.perf_counter()
            ids = model.generate(feats, max_new_tokens=440)
            latencies.append(time.perf_counter() - t0)

            hyp = proc.tokenizer.decode(ids[0], skip_special_tokens=True).strip()
            ref = r["text"].strip()
            refs.append(ref)
            hyps.append(hyp)

    wer = compute_wer(refs, hyps) if refs else 1.0
    # False positive = hyp non-empty when ref is non-empty but hyp very different
    # Simple proxy: WER > 0.8 on a clip → wrong
    fp = sum(1 for r, h in zip(refs, hyps)
             if h.strip() and compute_wer([r], [h]) > 0.8) / max(len(refs), 1)
    recall = sum(1 for r, h in zip(refs, hyps) if h.strip()) / max(len(refs), 1)

    return {
        "n":          len(refs),
        "wer":        round(wer, 4),
        "false_pos":  round(fp, 4),
        "recall":     round(recall, 4),
        "avg_lat_s":  round(float(np.mean(latencies)) if latencies else 0, 3),
    }


def model_size_mb(model_dir: str) -> float:
    total = 0
    for f in os.listdir(model_dir):
        p = os.path.join(model_dir, f)
        if os.path.isfile(p):
            total += os.path.getsize(p)
    return round(total / 1e6, 1)


# ── Quantization ──────────────────────────────────────────────────────────────

def apply_int8_dynamic(model) -> nn.Module:
    """PyTorch dynamic INT8 quantization (weights only, activations in float32).
    This is what LiteRT uses for Whisper-compatible deployment."""
    quantized = copy.deepcopy(model).cpu()
    quantized = torch.quantization.quantize_dynamic(
        quantized,
        qconfig_spec={nn.Linear, nn.Conv1d},
        dtype=torch.qint8,
    )
    return quantized


def try_int4(model_dir: str):
    """Load model in INT4 via bitsandbytes (if available)."""
    try:
        from transformers import BitsAndBytesConfig
        cfg = BitsAndBytesConfig(load_in_4bit=True, bnb_4bit_compute_dtype=torch.float16)
        m = WhisperForConditionalGeneration.from_pretrained(
            model_dir, quantization_config=cfg, device_map="auto")
        return m
    except Exception as e:
        print(f"  INT4 non disponible : {e}", flush=True)
        return None


# ── Main ──────────────────────────────────────────────────────────────────────

def benchmark_model_fmt(name: str, model_dir: str, fmt: str,
                         samples: dict[str, list]) -> list[dict]:
    """Evaluate one model × one quantization format."""
    cuda = torch.cuda.is_available()

    print(f"\n{'='*60}", flush=True)
    print(f"{name}  [{fmt}]", flush=True)

    proc = WhisperProcessor.from_pretrained(model_dir)

    # Load model in the requested format
    if fmt == "float32":
        device = "cuda" if cuda else "cpu"
        model  = WhisperForConditionalGeneration.from_pretrained(model_dir).to(device)
    elif fmt == "int8":
        base   = WhisperForConditionalGeneration.from_pretrained(model_dir)
        model  = apply_int8_dynamic(base)
        device = "cpu"   # dynamic INT8 runs on CPU
    elif fmt == "int4":
        model  = try_int4(model_dir)
        device = "cuda" if cuda else "cpu"
        if model is None:
            print(f"  INT4 non disponible — skip", flush=True)
            return []
    else:
        raise ValueError(f"Format inconnu : {fmt}")

    # Taille mobile estimée
    est_mb = (SIZE_ESTIMATES.get(name, {}).get(fmt)
              or round(model_size_mb(model_dir) / {"float32": 1, "int8": 3.5, "int4": 7}[fmt], 1))
    print(f"  Taille mobile estimée : {est_mb} MB", flush=True)

    results = []
    for test_name, sample in samples.items():
        print(f"  Eval {test_name} ({len(sample)} clips)...", flush=True)
        metrics = run_eval(model, proc, sample, test_name)
        results.append({
            "model":    name,
            "format":   fmt,
            "test":     test_name,
            "size_mb":  est_mb,
            **metrics,
        })
        print(f"    WER={metrics['wer']:.1%}  FP={metrics['false_pos']:.1%}  "
              f"lat={metrics['avg_lat_s']}s", flush=True)

    del model
    if cuda: torch.cuda.empty_cache()
    return results


def main():
    # Pre-load test samples (same for all 5 configurations)
    samples = {}
    for tname, tpath in TEST_SETS.items():
        if os.path.exists(tpath):
            samples[tname] = load_sample(tpath, N_SAMPLE)
            print(f"Test set {tname}: {len(samples[tname])} clips", flush=True)
        else:
            print(f"Test set manquant : {tpath}", flush=True)

    # Only the 5 meaningful mobile-deployment configurations
    PLAN = [
        ("base_ft",   "float32"),
        ("base_ft",   "int8"),
        ("small_ft",  "int8"),
        ("small_ft",  "int4"),
        ("medium_ft", "int4"),
    ]

    all_results = []
    for model_name, fmt in PLAN:
        model_dir = MODELS.get(model_name, "")
        if not os.path.exists(model_dir):
            print(f"\nSkip {model_name}/{fmt} — modèle absent", flush=True)
            continue
        results = benchmark_model_fmt(model_name, model_dir, fmt, samples)
        all_results.extend(results)

    # Save JSON
    out_json = os.path.join(RESULTS, "quant_benchmark.json")
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(all_results, f, indent=2, ensure_ascii=False)

    # Save CSV
    out_csv = os.path.join(RESULTS, "quant_benchmark.csv")
    with open(out_csv, "w", encoding="utf-8") as f:
        f.write("model,format,test,size_mb,wer,false_pos,recall,avg_lat_s\n")
        for r in all_results:
            f.write(f"{r['model']},{r['format']},{r['test']},"
                    f"{r['size_mb']},{r['wer']},{r['false_pos']},"
                    f"{r['recall']},{r['avg_lat_s']}\n")

    print(f"\n{'='*60}", flush=True)
    print("RÉSULTATS", flush=True)
    print(f"{'Modèle':<18} {'Format':<10} {'Test':<8} {'MB':>6} "
          f"{'WER':>7} {'FP':>7} {'Lat':>6}", flush=True)
    print("-" * 65, flush=True)
    for r in all_results:
        print(f"{r['model']:<18} {r['format']:<10} {r['test']:<8} "
              f"{r['size_mb']:>6} {r['wer']:>6.1%} {r['false_pos']:>6.1%} "
              f"{r['avg_lat_s']:>5}s", flush=True)

    print(f"\nSauvegardé → {out_json}", flush=True)
    print(f"Sauvegardé → {out_csv}", flush=True)
    print("QUANT BENCHMARK DONE", flush=True)


if __name__ == "__main__":
    main()
