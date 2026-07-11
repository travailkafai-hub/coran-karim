"""
Évaluation Nemotron / FastConformer Arabic ASR pour Coran Karim.

Stratégie :
  1. Essai via NeMo (nvidia/stt_ar_fastconformer_hybrid_large_pc) si installé
  2. Fallback : sherpa-onnx avec modèle ONNX communautaire
  3. Fallback 2 : tarteel-ai/whisper-base-ar-quran (baseline Coran spécialisé, WER 5.75%)

Objectif : comparer WER sur nos 200 clips de test vs nos modèles Whisper fine-tunés.

Usage:
  python nemotron_eval.py [--backend nemo|sherpa|tarteel] [--n 50]
"""
import os, sys
os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"
import truststore; truststore.inject_into_ssl()
import json, time, re, argparse
import numpy as np
import soundfile as sf
import torch
from jiwer import wer as compute_wer

os.environ.setdefault("HF_HOME", os.path.join(os.path.dirname(__file__), ".hf"))
ROOT     = os.path.dirname(os.path.abspath(__file__))
TEST_SET = os.path.join(ROOT, "data", "test_voice_full.jsonl")

_HAR = re.compile(r'[ً-ٰؐ-ؚۖ-ۭـ]')
def norm(t):
    t = _HAR.sub('', t)
    t = t.replace('أ','ا').replace('إ','ا').replace('آ','ا').replace('ى','ي').replace('ؤ','و').replace('ئ','ي')
    return re.sub(r'\s+',' ', re.sub(r'[^؀-ۿ\s]','',t)).strip()


# ── Tarteel baseline ──────────────────────────────────────────────────────────

def eval_tarteel(rows):
    """tarteel-ai/whisper-base-ar-quran — spécialisé Coran, WER 5.75% sans harakat."""
    from transformers import WhisperProcessor, WhisperForConditionalGeneration
    MODEL_ID = "tarteel-ai/whisper-base-ar-quran"
    print(f"\nChargement {MODEL_ID}...", flush=True)
    proc  = WhisperProcessor.from_pretrained(MODEL_ID)
    model = WhisperForConditionalGeneration.from_pretrained(MODEL_ID)
    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = model.to(device).eval()

    try:
        model.generation_config.is_multilingual = True
        model.generation_config.forced_decoder_ids = proc.get_decoder_prompt_ids(
            language="arabic", task="transcribe")
        model.generation_config.suppress_tokens = []
    except Exception:
        pass

    refs, hyps, lats = [], [], []
    with torch.no_grad():
        for r in rows:
            p = os.path.join(ROOT, r["wav"])
            if not os.path.exists(p): continue
            audio, _ = sf.read(p, dtype="float32")
            feats = proc.feature_extractor(audio, sampling_rate=16000,
                                           return_tensors="pt").input_features.to(device)
            t0 = time.perf_counter()
            ids = model.generate(feats, max_new_tokens=440)
            lats.append(time.perf_counter() - t0)
            hyp = proc.tokenizer.decode(ids[0], skip_special_tokens=True).strip()
            refs.append(r["text"])
            hyps.append(hyp)

    # WER avec harakat (comme nos modèles)
    wer_raw  = compute_wer(refs, hyps)
    # WER sans harakat (comme le papier tarteel)
    wer_norm = compute_wer([norm(r) for r in refs], [norm(h) for h in hyps])
    lat_avg  = float(np.mean(lats)) if lats else 0

    print(f"\n{'='*55}", flush=True)
    print(f"tarteel-ai/whisper-base-ar-quran", flush=True)
    print(f"  WER (avec harakat) : {wer_raw:.1%}", flush=True)
    print(f"  WER (sans harakat) : {wer_norm:.1%}  ← comparable au papier 5.75%", flush=True)
    print(f"  Latence moyenne    : {lat_avg:.3f}s", flush=True)
    print(f"  N clips            : {len(refs)}", flush=True)
    return {"backend": "tarteel", "wer_raw": round(wer_raw,4),
            "wer_norm": round(wer_norm,4), "avg_lat_s": round(lat_avg,3), "n": len(refs)}


# ── NeMo FastConformer ────────────────────────────────────────────────────────

def eval_nemo(rows):
    try:
        import nemo.collections.asr as nemo_asr
    except ImportError:
        print("NeMo non installé — pip install nemo_toolkit[asr]", flush=True)
        return None

    MODEL_ID = "nvidia/stt_ar_fastconformer_hybrid_large_pc"
    print(f"\nChargement {MODEL_ID} via NeMo...", flush=True)
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.from_pretrained(MODEL_ID)
    model = model.eval()

    # Écrire les wavs dans un fichier manifest temporaire
    import tempfile
    valid = [r for r in rows if os.path.exists(os.path.join(ROOT, r["wav"]))]
    manifest_tmp = os.path.join(ROOT, "results", "_nemo_tmp_manifest.jsonl")
    with open(manifest_tmp, "w", encoding="utf-8") as f:
        for r in valid:
            f.write(json.dumps({"audio_filepath": os.path.join(ROOT, r["wav"]),
                                "duration": 10, "text": r["text"]},
                               ensure_ascii=False) + "\n")

    t0 = time.time()
    hyps = model.transcribe([os.path.join(ROOT, r["wav"]) for r in valid])
    elapsed = time.time() - t0

    refs = [r["text"] for r in valid]
    wer_raw  = compute_wer(refs, hyps)
    wer_norm = compute_wer([norm(r) for r in refs], [norm(h) for h in hyps])

    print(f"\n{'='*55}", flush=True)
    print(f"NeMo stt_ar_fastconformer_hybrid_large_pc", flush=True)
    print(f"  WER (avec harakat) : {wer_raw:.1%}", flush=True)
    print(f"  WER (sans harakat) : {wer_norm:.1%}", flush=True)
    print(f"  Latence totale     : {elapsed:.1f}s pour {len(valid)} clips", flush=True)
    return {"backend": "nemo_fastconformer", "wer_raw": round(wer_raw,4),
            "wer_norm": round(wer_norm,4), "n": len(valid)}


# ── sherpa-onnx ───────────────────────────────────────────────────────────────

def eval_sherpa(rows):
    try:
        import sherpa_onnx
    except ImportError:
        print("sherpa-onnx non installé — pip install sherpa-onnx", flush=True)
        return None

    # Recherche d'un modèle Arabic dans sherpa-onnx
    # Modèles connus avec support arabe :
    #   sherpa-onnx-whisper-medium-ar (sur GitHub release)
    #   streaming transducer custom
    # Pour l'instant, on liste ce qui est disponible localement
    model_dir = os.path.join(ROOT, "models", "sherpa-arabic")
    if not os.path.isdir(model_dir):
        print(f"Aucun modèle sherpa-onnx trouvé dans {model_dir}", flush=True)
        print("Télécharger un modèle Arabic, ex:", flush=True)
        print("  sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20", flush=True)
        print("  (voir k2-fsa.github.io/sherpa/onnx/pretrained_models/)", flush=True)
        return None

    print(f"sherpa-onnx : modèle dans {model_dir}", flush=True)
    # TODO: configurer le recognizer selon le modèle téléchargé
    return None


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--backend", choices=["tarteel","nemo","sherpa","all"],
                    default="tarteel")
    ap.add_argument("--n", type=int, default=100,
                    help="Nombre de clips à évaluer (max test_voice_full)")
    args = ap.parse_args()

    rows = [json.loads(l) for l in open(TEST_SET, encoding="utf-8")]
    rng  = np.random.default_rng(42)
    idx  = rng.choice(len(rows), min(args.n, len(rows)), replace=False)
    rows = [rows[i] for i in idx]
    print(f"Éval sur {len(rows)} clips de test_voice_full", flush=True)
    print(f"CUDA: {torch.cuda.is_available()} | "
          f"{torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU'}",
          flush=True)

    results = []
    if args.backend in ("tarteel", "all"):
        r = eval_tarteel(rows)
        if r: results.append(r)
    if args.backend in ("nemo", "all"):
        r = eval_nemo(rows)
        if r: results.append(r)
    if args.backend in ("sherpa", "all"):
        r = eval_sherpa(rows)
        if r: results.append(r)

    if results:
        out = os.path.join(ROOT, "results", "nemotron_eval.json")
        with open(out, "w", encoding="utf-8") as f:
            json.dump(results, f, indent=2, ensure_ascii=False)
        print(f"\nRésultats sauvegardés → {out}", flush=True)
    print("NEMOTRON EVAL DONE", flush=True)


if __name__ == "__main__":
    main()
