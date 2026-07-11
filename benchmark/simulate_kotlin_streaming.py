"""
Reproduit EXACTEMENT le pipeline streaming Kotlin (FastConformerStreamingSession v2)
en Python, sur un clip de validation connu, pour diagnostiquer hors-device la
quasi-absence de texte decode observee sur telephone (v10) :
  preemphase -> frames mel causales -> normalisation (3 strategies comparees)
  -> fenetres 25 frames avancant de 16 -> ONNX streaming avec cache -> greedy.

Strategies de normalisation comparees :
  A) cumulative : stats mean/std sur TOUTES les frames depuis le debut (= Kotlin v10)
  B) sliding    : stats sur les ~10 dernieres secondes (fenetre glissante)
  C) oracle     : stats sur l'enonce complet (= ce que le modele attend, non-causal,
                  juste pour verifier le plafond de qualite atteignable)
Chaque strategie est testee avec et sans 3s de silence prepende (conditions device).
"""
import os, json, random
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import numpy as np, onnxruntime as ort, soundfile as sf
from pathlib import Path
from mel_numpy_reference import hann_window_periodic_false, mel_filterbank_slaney

BASE_DIR = Path(__file__).parent
ONNX_PATH = BASE_DIR / "models" / "fastconformer-quran-pcd" / "onnx_streaming" / "fastconformer_ctc_streaming.onnx"

N_MELS, N_FFT, WIN_LEN, HOP, PREEMPH = 80, 512, 400, 160, 0.97
WIN_PAD = (N_FFT - WIN_LEN) // 2
CENTER_PAD = N_FFT // 2
CHUNK_FRAMES, PRE_CACHE = 16, 9
WINDOW = CHUNK_FRAMES + PRE_CACHE
LOG_GUARD = 2.0 ** -24
NUM_LAYERS, CACHE_LEN, D_MODEL, TIME_CACHE = 17, 70, 512, 4

window_fn = hann_window_periodic_false(WIN_LEN)
fb = mel_filterbank_slaney(sr=16000, n_fft=N_FFT, n_mels=N_MELS).astype(np.float64)

import sentencepiece  # noqa: F401 (juste pour verifier dispo si besoin)


def causal_log_mel_frames(audio: np.ndarray) -> np.ndarray:
    """Frames log-mel NON normalisees, calcul strictement causal (= Kotlin v2)."""
    x = np.empty_like(audio, dtype=np.float64)
    x[0] = audio[0]
    x[1:] = audio[1:] - PREEMPH * audio[:-1]
    padded = np.concatenate([np.zeros(CENTER_PAD), x])
    frames = []
    t = 0
    while t * HOP + WIN_PAD + WIN_LEN <= len(padded):
        seg = padded[t*HOP + WIN_PAD : t*HOP + WIN_PAD + WIN_LEN] * window_fn
        frame = np.zeros(N_FFT)
        frame[WIN_PAD:WIN_PAD+WIN_LEN] = seg
        spec = np.fft.rfft(frame)
        power = np.abs(spec) ** 2
        mel = fb @ power
        frames.append(np.log(mel + LOG_GUARD))
        t += 1
    return np.array(frames)  # (T, 80)


def run_streaming(log_mel: np.ndarray, sess, tokenizer, norm_mode: str) -> str:
    T = log_mel.shape[0]
    cache_ch = np.zeros((1, NUM_LAYERS, CACHE_LEN, D_MODEL), dtype=np.float32)
    cache_t = np.zeros((1, NUM_LAYERS, D_MODEL, TIME_CACHE), dtype=np.float32)
    cache_len = np.zeros((1,), dtype=np.int64)

    decoded, prev = [], -1
    end = CHUNK_FRAMES
    while end <= T:
        avail = log_mel[:end]
        if norm_mode == "cumulative":
            stats_src = avail
        elif norm_mode == "sliding":
            stats_src = avail[-1000:]  # ~10s
        elif norm_mode == "oracle":
            stats_src = log_mel
        mean = stats_src.mean(axis=0)
        std = stats_src.std(axis=0, ddof=1) if len(stats_src) > 1 else np.ones(N_MELS)
        std = std + 1e-5

        win = avail[max(0, end-WINDOW):end]
        normed = (win - mean) / std
        missing = WINDOW - normed.shape[0]
        if missing > 0:
            normed = np.concatenate([np.zeros((missing, N_MELS)), normed])

        feats = normed.T[None].astype(np.float32)  # (1, 80, 25)
        out = sess.run(None, {
            "audio_signal": feats,
            "length": np.array([WINDOW], dtype=np.int64),
            "cache_last_channel": cache_ch,
            "cache_last_time": cache_t,
            "cache_last_channel_len": cache_len,
        })
        logprobs, cache_ch, cache_t, cache_len_arr = out
        cache_len = np.atleast_1d(cache_len_arr).astype(np.int64)

        ids = logprobs[0].argmax(axis=-1)
        for i in ids:
            if i != prev and i != logprobs.shape[-1] - 1:
                decoded.append(int(i))
            prev = i
        end += CHUNK_FRAMES

    return tokenizer.ids_to_text(decoded)


def main():
    import nemo.collections.asr as nemo_asr
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        str(BASE_DIR / "models" / "fastconformer-quran-pcd" / "fastconformer-quran-pcd-snapshot.nemo"),
        map_location="cpu")
    tokenizer = model.tokenizer
    del model

    sess = ort.InferenceSession(str(ONNX_PATH), providers=["CPUExecutionProvider"])

    rows = [json.loads(l) for l in open(BASE_DIR/"nemo_manifests"/"val_manifest.jsonl", encoding="utf-8")]
    random.seed(7)
    r = random.choice(rows)
    audio, sr = sf.read(r["audio_filepath"], dtype="float32")
    print("REF :", r["text"])

    for silence_s in [0.0, 3.0]:
        sig = np.concatenate([np.zeros(int(16000*silence_s), dtype=np.float32), audio])
        log_mel = causal_log_mel_frames(sig)
        print(f"\n--- silence prepend = {silence_s}s | frames = {log_mel.shape[0]} ---")
        for mode in ["cumulative", "sliding", "oracle"]:
            txt = run_streaming(log_mel, sess, tokenizer, mode)
            print(f"[{mode:10s}] {txt}")


if __name__ == "__main__":
    main()
