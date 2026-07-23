"""
NeMo FastConformer Arabic ASR Evaluation — Coran Karim benchmark.

Stratégie :
  1. NeMo avec nvidia/stt_ar_fastconformer_hybrid_large_pc_v1.0 (424 MB, .nemo depuis HF)
  2. NeMo avec NightPrince/stt-ar-fastconformer-quran-minshawi (459 MB, spécialisé Coran)
  3. sherpa-onnx avec dev-ahmedhany CTC encoder (456 MB, CTC simple)
  4. sherpa-onnx avec LukeJacob2023 transducer (encoder 456 MB + decoder/joiner)

Usage:
  python nemotron_nemo_eval.py [--backend nemo|nemo_quran|sherpa_ctc|sherpa_rnnt|all] [--n 50]

Résultats sauvegardés dans results/nemotron_nemo_eval.json
Logs dans logs/nemotron_nemo.log
"""
import os, sys
# CRITIQUE : mettre USE_TF=0 AVANT tout import pour éviter le bug TF transformers 4.57.6
os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import json, time, re, argparse, logging, traceback
import numpy as np
import soundfile as sf
from jiwer import wer as jiwer_wer
import torch

# SSL fix
try:
    import truststore
    truststore.inject_into_ssl()
except ImportError:
    pass

ROOT     = os.path.dirname(os.path.abspath(__file__))
TEST_SET = os.path.join(ROOT, "data", "test_voice_full.jsonl")
RESULTS_DIR = os.path.join(ROOT, "results")
LOGS_DIR    = os.path.join(ROOT, "logs")
MODELS_DIR  = os.path.join(ROOT, "models")
HF_HOME     = os.path.join(ROOT, ".hf")
NEMO_CACHE  = os.path.join(ROOT, ".hf", "nemo_models")

os.makedirs(RESULTS_DIR, exist_ok=True)
os.makedirs(LOGS_DIR,    exist_ok=True)
os.makedirs(NEMO_CACHE,  exist_ok=True)
os.environ.setdefault("HF_HOME", HF_HOME)

# ── Logging ───────────────────────────────────────────────────────────────────
log_path = os.path.join(LOGS_DIR, "nemotron_nemo.log")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler(log_path, encoding="utf-8"),
        logging.StreamHandler(sys.stdout),
    ]
)
log = logging.getLogger(__name__)

# ── Normalisation arabe ───────────────────────────────────────────────────────
_HAR = re.compile(r'[ً-ٰؐ-ؚۖ-ۭـ]')

def norm(t: str) -> str:
    """Supprime harakat, uniformise les variantes alef/ya/waw."""
    t = _HAR.sub('', t)
    t = (t.replace('أ', 'ا').replace('إ', 'ا').replace('آ', 'ا')
          .replace('ٱ', 'ا').replace('ى', 'ي')
          .replace('ؤ', 'و').replace('ئ', 'ي'))
    return re.sub(r'\s+', ' ', re.sub(r'[^؀-ۿ\s]', '', t)).strip()


def compute_wer(refs, hyps, normalize_fn=None):
    """WER corpus-level (jiwer)."""
    if normalize_fn:
        refs = [normalize_fn(r) for r in refs]
        hyps = [normalize_fn(h) for h in hyps]
    return jiwer_wer(refs, hyps)


# ── Load test clips ───────────────────────────────────────────────────────────
def load_clips(n=50, seed=42):
    rows = [json.loads(l) for l in open(TEST_SET, encoding="utf-8")]
    rng  = np.random.default_rng(seed)
    idx  = rng.choice(len(rows), min(n, len(rows)), replace=False)
    clips = [rows[i] for i in idx]
    # Filter to existing wavs
    valid = [r for r in clips if os.path.exists(os.path.join(ROOT, r["wav"]))]
    log.info(f"Clips chargés : {len(valid)}/{len(clips)} (manquants: {len(clips)-len(valid)})")
    return valid


# ── NeMo FastConformer standard ───────────────────────────────────────────────
def download_nemo_model(hf_repo: str, filename: str) -> str:
    """Télécharge un fichier .nemo depuis HuggingFace dans le cache local."""
    from huggingface_hub import hf_hub_download
    local_path = os.path.join(NEMO_CACHE, filename)
    if os.path.exists(local_path):
        log.info(f"Modèle .nemo trouvé en cache : {local_path}")
        return local_path
    log.info(f"Telechargement {hf_repo}/{filename} -> {local_path}")
    downloaded = hf_hub_download(
        repo_id=hf_repo,
        filename=filename,
        local_dir=NEMO_CACHE,
        local_dir_use_symlinks=False,
    )
    return downloaded


def eval_nemo(rows, hf_repo: str, filename: str, label: str):
    """Évalue un modèle NeMo .nemo sur les clips de test."""
    try:
        import nemo.collections.asr as nemo_asr
    except ImportError as e:
        log.error(f"NeMo non installé : {e}")
        return None

    log.info(f"\n{'='*60}")
    log.info(f"Backend : NeMo — {label}")
    log.info(f"Repo    : {hf_repo}")

    # Télécharger le modèle
    try:
        nemo_path = download_nemo_model(hf_repo, filename)
    except Exception as e:
        log.error(f"Échec téléchargement {hf_repo}: {e}")
        log.error(traceback.format_exc())
        return None

    # Charger le modèle NeMo
    log.info(f"Chargement du modèle NeMo depuis {nemo_path}...")
    t_load = time.time()
    try:
        model = nemo_asr.models.ASRModel.restore_from(nemo_path)
        model = model.eval()
        if torch.cuda.is_available():
            model = model.cuda()
    except Exception as e:
        log.error(f"Erreur chargement modèle NeMo : {e}")
        log.error(traceback.format_exc())
        return None
    load_time = time.time() - t_load
    log.info(f"Modèle chargé en {load_time:.1f}s")

    # Taille modèle
    model_size_mb = os.path.getsize(nemo_path) / 1e6
    n_params = sum(p.numel() for p in model.parameters()) / 1e6
    log.info(f"Taille fichier : {model_size_mb:.1f} MB | Paramètres : {n_params:.1f}M")

    # Transcription
    wav_paths = [os.path.join(ROOT, r["wav"]) for r in rows]
    refs = [r["text"] for r in rows]

    log.info(f"Transcription de {len(wav_paths)} clips...")
    t0 = time.time()
    try:
        hyps_raw = model.transcribe(wav_paths, batch_size=8)
        # Certains modèles retournent (hyps, scores) ou juste hyps
        if isinstance(hyps_raw, tuple):
            hyps_raw = hyps_raw[0]
        # NeMo retourne parfois des objets Hypothesis - extraire le texte
        hyps = []
        for h in hyps_raw:
            if hasattr(h, 'text'):
                hyps.append(h.text or '')
            elif isinstance(h, str):
                hyps.append(h)
            else:
                hyps.append(str(h))
    except Exception as e:
        log.error(f"Erreur transcription : {e}")
        log.error(traceback.format_exc())
        return None
    elapsed = time.time() - t0

    # WER
    wer_raw  = compute_wer(refs, hyps)
    wer_norm = compute_wer(refs, hyps, normalize_fn=norm)
    avg_lat  = elapsed / len(wav_paths)

    log.info(f"\n{'='*60}")
    log.info(f"Modèle : {label}")
    log.info(f"  WER brut (avec harakat) : {wer_raw:.1%}")
    log.info(f"  WER normalisé           : {wer_norm:.1%}")
    log.info(f"  Latence totale          : {elapsed:.1f}s pour {len(wav_paths)} clips")
    log.info(f"  Latence / clip          : {avg_lat:.3f}s")
    log.info(f"  Comparaison vs small_ft WER 19.1%, medium_ft WER 10.75%")

    # Quelques exemples
    for i in range(min(3, len(refs))):
        log.info(f"  Ref : {norm(refs[i])[:80]}")
        h = hyps[i] if isinstance(hyps[i], str) else str(hyps[i])
        log.info(f"  Hyp : {norm(h)[:80]}")
        log.info("")

    return {
        "backend": label,
        "hf_repo": hf_repo,
        "wer_raw": round(wer_raw, 4),
        "wer_norm": round(wer_norm, 4),
        "avg_lat_s": round(avg_lat, 3),
        "total_s": round(elapsed, 1),
        "model_mb": round(model_size_mb, 1),
        "n_params_M": round(n_params, 1),
        "n": len(wav_paths),
        "vs_small_ft": f"{'MEILLEUR' if wer_norm < 0.191 else 'moins bon'} que small_ft (19.1%)",
        "vs_medium_ft": f"{'MEILLEUR' if wer_norm < 0.1075 else 'moins bon'} que medium_ft (10.75%)",
    }


# ── sherpa-onnx CTC ──────────────────────────────────────────────────────────
def download_sherpa_model(hf_repo: str, files: list, subdir: str) -> str:
    """Télécharge les fichiers sherpa-onnx depuis HuggingFace."""
    from huggingface_hub import hf_hub_download
    model_dir = os.path.join(MODELS_DIR, subdir)
    os.makedirs(model_dir, exist_ok=True)
    for fname in files:
        local_path = os.path.join(model_dir, fname)
        if not os.path.exists(local_path):
            log.info(f"Téléchargement {hf_repo}/{fname}...")
            hf_hub_download(
                repo_id=hf_repo,
                filename=fname,
                local_dir=model_dir,
                local_dir_use_symlinks=False,
            )
        else:
            log.info(f"Cache : {local_path}")
    return model_dir


def eval_sherpa_ctc(rows):
    """sherpa-onnx avec FastConformer CTC Arabic (dev-ahmedhany)."""
    try:
        import sherpa_onnx
    except ImportError as e:
        log.error(f"sherpa-onnx non installé : {e}")
        return None

    REPO = "dev-ahmedhany/stt_ar_fastconformer_hybrid_large_pcd_v1.0-sherpa-ctc"
    FILES = ["encoder.onnx", "tokens.txt"]
    TOKENS_FIXED = "tokens_blk_nobom.txt"  # version avec <blk> 0 prepend, sans BOM

    log.info(f"\n{'='*60}")
    log.info(f"Backend : sherpa-onnx CTC")
    log.info(f"Repo    : {REPO}")

    try:
        model_dir = download_sherpa_model(REPO, FILES, "sherpa-arabic-ctc")
    except Exception as e:
        log.error(f"Échec téléchargement sherpa CTC : {e}")
        return None

    encoder_path = os.path.join(model_dir, "encoder.onnx")
    tokens_raw   = os.path.join(model_dir, "tokens.txt")
    tokens_path  = os.path.join(model_dir, "tokens_blk_nobom.txt")

    # Creer tokens fixe si necessaire (ajouter <blk> 0 en tete, supprimer BOM)
    if not os.path.exists(tokens_path):
        log.info("Creation du tokens.txt fixe avec <blk> 0...")
        with open(tokens_raw, "r", encoding="utf-8-sig") as f:
            content = f.read()
        fixed = "<blk> 0\n" + content
        with open(tokens_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(fixed)
        log.info(f"Tokens fixe cree : {tokens_path}")

    log.info("Initialisation sherpa-onnx CTC recognizer...")
    try:
        recognizer = sherpa_onnx.OfflineRecognizer.from_nemo_ctc(
            model=encoder_path,
            tokens=tokens_path,
            num_threads=4,
            decoding_method="greedy_search",
        )
    except Exception as e:
        log.error(f"Erreur init recognizer CTC : {e}")
        log.error(traceback.format_exc())
        return None

    refs, hyps, lats = [], [], []
    model_size_mb = os.path.getsize(encoder_path) / 1e6

    log.info(f"Transcription de {len(rows)} clips...")
    for r in rows:
        p = os.path.join(ROOT, r["wav"])
        try:
            audio, sr = sf.read(p, dtype="float32")
            if sr != 16000:
                # Resample basique si nécessaire
                import scipy.signal
                audio = scipy.signal.resample(audio, int(len(audio) * 16000 / sr))
            stream = recognizer.create_stream()
            stream.accept_waveform(16000, audio)
            recognizer.decode_stream(stream)
            t0 = time.perf_counter()
            recognizer.decode_stream(stream)
            lats.append(time.perf_counter() - t0)
            hyp = stream.result.text.strip()
            refs.append(r["text"])
            hyps.append(hyp)
        except Exception as e:
            log.warning(f"Erreur sur {p}: {e}")

    wer_raw  = compute_wer(refs, hyps)
    wer_norm = compute_wer(refs, hyps, normalize_fn=norm)
    avg_lat  = float(np.mean(lats)) if lats else 0

    log.info(f"\n{'='*60}")
    log.info(f"sherpa-onnx CTC FastConformer Arabic")
    log.info(f"  WER brut (avec harakat) : {wer_raw:.1%}")
    log.info(f"  WER normalisé           : {wer_norm:.1%}")
    log.info(f"  Latence / clip          : {avg_lat:.3f}s")
    log.info(f"  Taille encoder          : {model_size_mb:.1f} MB")
    log.info(f"  Comparaison : small_ft 19.1%, medium_ft 10.75%")

    return {
        "backend": "sherpa_ctc_fastconformer_ar",
        "hf_repo": REPO,
        "wer_raw": round(wer_raw, 4),
        "wer_norm": round(wer_norm, 4),
        "avg_lat_s": round(avg_lat, 3),
        "model_mb": round(model_size_mb, 1),
        "n": len(refs),
        "vs_small_ft": f"{'MEILLEUR' if wer_norm < 0.191 else 'moins bon'} que small_ft (19.1%)",
        "vs_medium_ft": f"{'MEILLEUR' if wer_norm < 0.1075 else 'moins bon'} que medium_ft (10.75%)",
    }


def eval_sherpa_rnnt(rows):
    """sherpa-onnx avec FastConformer RNNT Arabic (LukeJacob2023, transducer)."""
    try:
        import sherpa_onnx
    except ImportError as e:
        log.error(f"sherpa-onnx non installé : {e}")
        return None

    REPO = "LukeJacob2023/sherpa-onnx-stt_ar_fastconformer_hybrid_large_pc"
    FILES = ["encoder.onnx", "decoder.onnx", "joiner.onnx", "tokens.txt"]

    log.info(f"\n{'='*60}")
    log.info(f"Backend : sherpa-onnx RNNT (transducer)")
    log.info(f"Repo    : {REPO}")

    try:
        model_dir = download_sherpa_model(REPO, FILES, "sherpa-arabic-rnnt")
    except Exception as e:
        log.error(f"Échec téléchargement sherpa RNNT : {e}")
        return None

    encoder_path = os.path.join(model_dir, "encoder.onnx")
    decoder_path = os.path.join(model_dir, "decoder.onnx")
    joiner_path  = os.path.join(model_dir, "joiner.onnx")
    tokens_path  = os.path.join(model_dir, "tokens.txt")

    log.info("Initialisation sherpa-onnx RNNT recognizer...")
    try:
        recognizer = sherpa_onnx.OfflineRecognizer.from_transducer(
            encoder=encoder_path,
            decoder=decoder_path,
            joiner=joiner_path,
            tokens=tokens_path,
            num_threads=4,
            decoding_method="greedy_search",
        )
    except Exception as e:
        log.error(f"Erreur init recognizer RNNT : {e}")
        log.error(traceback.format_exc())
        return None

    refs, hyps, lats = [], [], []
    encoder_mb = os.path.getsize(encoder_path) / 1e6

    log.info(f"Transcription de {len(rows)} clips...")
    for r in rows:
        p = os.path.join(ROOT, r["wav"])
        try:
            audio, sr = sf.read(p, dtype="float32")
            stream = recognizer.create_stream()
            stream.accept_waveform(16000, audio)
            t0 = time.perf_counter()
            recognizer.decode_stream(stream)
            lats.append(time.perf_counter() - t0)
            hyp = stream.result.text.strip()
            refs.append(r["text"])
            hyps.append(hyp)
        except Exception as e:
            log.warning(f"Erreur sur {p}: {e}")

    if not refs:
        log.error("Aucune transcription réussie")
        return None

    wer_raw  = compute_wer(refs, hyps)
    wer_norm = compute_wer(refs, hyps, normalize_fn=norm)
    avg_lat  = float(np.mean(lats)) if lats else 0

    log.info(f"\n{'='*60}")
    log.info(f"sherpa-onnx RNNT FastConformer Arabic")
    log.info(f"  WER brut (avec harakat) : {wer_raw:.1%}")
    log.info(f"  WER normalisé           : {wer_norm:.1%}")
    log.info(f"  Latence / clip          : {avg_lat:.3f}s")
    log.info(f"  Taille encoder          : {encoder_mb:.1f} MB")

    return {
        "backend": "sherpa_rnnt_fastconformer_ar",
        "hf_repo": REPO,
        "wer_raw": round(wer_raw, 4),
        "wer_norm": round(wer_norm, 4),
        "avg_lat_s": round(avg_lat, 3),
        "model_mb": round(encoder_mb, 1),
        "n": len(refs),
        "vs_small_ft": f"{'MEILLEUR' if wer_norm < 0.191 else 'moins bon'} que small_ft (19.1%)",
        "vs_medium_ft": f"{'MEILLEUR' if wer_norm < 0.1075 else 'moins bon'} que medium_ft (10.75%)",
    }


# ── Summary ───────────────────────────────────────────────────────────────────
def print_summary(results: list):
    log.info("\n" + "="*65)
    log.info("RÉSUMÉ COMPARATIF")
    log.info("="*65)
    log.info(f"{'Modèle':<40} {'WER norm':>9} {'Lat/clip':>9}")
    log.info("-"*65)
    baselines = [
        ("whisper-small-ft (baseline)", 0.191, "~0.3s"),
        ("whisper-medium-ft (baseline)", 0.1075, "~0.8s"),
    ]
    for name, wer_b, lat in baselines:
        log.info(f"  {name:<38} {wer_b:>8.1%} {lat:>9}")
    log.info("-"*65)
    for r in results:
        name = r.get("backend", "?")[:38]
        wer  = r.get("wer_norm", r.get("wer_raw", 0))
        lat  = f"{r.get('avg_lat_s', 0):.3f}s"
        flag = "★ MEILLEUR" if wer < 0.1075 else ("↑" if wer < 0.191 else "↓")
        log.info(f"  {name:<38} {wer:>8.1%} {lat:>9}  {flag}")
    log.info("="*65)


# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(description="NeMo / sherpa-onnx Arabic ASR eval")
    ap.add_argument("--backend", default="nemo",
                    choices=["nemo", "nemo_quran", "sherpa_ctc", "sherpa_rnnt", "all"],
                    help="Backend à évaluer")
    ap.add_argument("--n", type=int, default=50,
                    help="Nombre de clips à évaluer (défaut 50)")
    args = ap.parse_args()

    log.info("="*65)
    log.info("NeMo FastConformer Arabic ASR — Evaluation Coran Karim")
    log.info("="*65)
    log.info(f"Backend : {args.backend} | N clips : {args.n}")
    log.info(f"CUDA    : {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        log.info(f"GPU     : {torch.cuda.get_device_name(0)}")
    log.info(f"HF_HOME : {HF_HOME}")
    log.info(f"NEMO cache : {NEMO_CACHE}")

    rows = load_clips(n=args.n)
    results = []

    if args.backend in ("nemo", "all"):
        r = eval_nemo(
            rows,
            hf_repo="nvidia/stt_ar_fastconformer_hybrid_large_pc_v1.0",
            filename="stt_ar_fastconformer_hybrid_large_pc_v1.0.nemo",
            label="nemo_fastconformer_ar_large_pc",
        )
        if r:
            results.append(r)

    if args.backend in ("nemo_quran", "all"):
        r = eval_nemo(
            rows,
            hf_repo="NightPrince/stt-ar-fastconformer-quran-minshawi",
            filename="quran_minshawi_final.nemo",
            label="nemo_fastconformer_ar_quran_minshawi",
        )
        if r:
            results.append(r)

    if args.backend in ("sherpa_ctc", "all"):
        r = eval_sherpa_ctc(rows)
        if r:
            results.append(r)

    if args.backend in ("sherpa_rnnt", "all"):
        r = eval_sherpa_rnnt(rows)
        if r:
            results.append(r)

    if results:
        print_summary(results)
        out = os.path.join(RESULTS_DIR, "nemotron_nemo_eval.json")
        # Charger resultats existants et fusionner (ne pas ecraser)
        existing = []
        if os.path.exists(out):
            try:
                with open(out, "r", encoding="utf-8") as fexist:
                    existing = json.load(fexist)
            except Exception:
                existing = []
        existing_names = {r["backend"] for r in existing}
        for r in results:
            if r["backend"] in existing_names:
                existing = [r if r2["backend"] == r["backend"] else r2 for r2 in existing]
            else:
                existing.append(r)
        with open(out, "w", encoding="utf-8") as f:
            json.dump(existing, f, indent=2, ensure_ascii=False)
        log.info(f"\nRésultats sauvegardés -> {out}")
    else:
        log.warning("Aucun résultat obtenu. Vérifier les logs.")

    log.info("NEMOTRON NEMO EVAL DONE")


if __name__ == "__main__":
    main()
