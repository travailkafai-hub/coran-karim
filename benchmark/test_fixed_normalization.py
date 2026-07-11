"""
Valide (ou invalide) le remplacement de la normalisation "per_feature"
(mean/std recalcules sur chaque enonce/buffer) par des statistiques FIXES
precalculees sur le corpus d'entrainement — la cause racine de la derive du
suivi en direct (voir SKILL.md "Streaming CTC", fix v3 BufferedTranscriber).

Protocole :
  1. Estimer mean/std par bande mel (80 valeurs chacun) sur un echantillon du
     corpus d'entrainement (mels NON normalises).
  2. WER sur clips isoles de validation : per_feature vs stats fixes.
     -> mesure le cout de precision "constant" du changement.
  3. WER sur audio CONCATENE (sessions synthetiques de 5-10 versets avec
     300ms de silence entre chaque, comme le buffer reel apres plafonnement) :
     per_feature vs stats fixes, en comparant la qualite des DERNIERS versets
     de chaque session (la ou la derive frappe le plus).
     -> mesure si les stats fixes eliminent bien la derive.

Critere d'adoption : WER stats-fixes sur clips isoles <= per_feature + ~0.5 pt
absolu ET degradation de fin de session eliminee sur l'audio concatene.

Sortie : mel_fixed_stats.json (mean/std par bande, pour le portage Kotlin).
"""
import os, sys, json, random
os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import numpy as np
import onnxruntime as ort
import soundfile as sf
from pathlib import Path

BASE_DIR = Path(__file__).parent
ONNX = BASE_DIR / "models" / "fastconformer-quran-pcd" / "onnx_export" / "fastconformer_ctc_pcd.onnx"
VOCAB = BASE_DIR / "models" / "fastconformer-quran-pcd" / "onnx_export" / "vocab_pieces.json"
VAL_MANIFEST = BASE_DIR / "nemo_manifests" / "val_manifest.jsonl"
TRAIN_MANIFEST = BASE_DIR / "nemo_manifests" / "train_manifest.jsonl"
STATS_OUT = BASE_DIR / "models" / "fastconformer-quran-pcd" / "onnx_export" / "mel_fixed_stats.json"

N_STATS_CLIPS = 300     # clips d'entrainement pour estimer les stats fixes
N_EVAL_CLIPS = 150      # clips de validation isoles pour le WER
N_SESSIONS = 12         # sessions synthetiques concatenees
VERSES_PER_SESSION = 7
SILENCE_S = 0.3         # silence conserve entre versets (= plafond Kotlin)
SR = 16000

# ── Mel (replication exacte de mel_numpy_reference.py, sans normalisation) ──
N_FFT, WIN, HOP, N_MELS = 512, 400, 160, 80
PREEMPH = 0.97
NORM_EPS = 1e-5


def _mel_filterbank():
    def hz_to_mel(f):
        return 2595.0 * np.log10(1.0 + f / 700.0)

    def mel_to_hz(m):
        return 700.0 * (10.0 ** (m / 2595.0) - 1.0)

    fmin, fmax = 0.0, SR / 2.0
    mels = np.linspace(hz_to_mel(fmin), hz_to_mel(fmax), N_MELS + 2)
    freqs = mel_to_hz(mels)
    bins = np.floor((N_FFT + 1) * freqs / SR).astype(int)
    fft_freqs = np.arange(N_FFT // 2 + 1) * SR / N_FFT
    fb = np.zeros((N_MELS, N_FFT // 2 + 1))
    for m in range(N_MELS):
        f_lo, f_c, f_hi = freqs[m], freqs[m + 1], freqs[m + 2]
        for k, f in enumerate(fft_freqs):
            if f_lo <= f <= f_c and f_c > f_lo:
                fb[m, k] = (f - f_lo) / (f_c - f_lo)
            elif f_c <= f <= f_hi and f_hi > f_c:
                fb[m, k] = (f_hi - f) / (f_hi - f_c)
        # normalisation slaney
        enorm = 2.0 / (freqs[m + 2] - freqs[m])
        fb[m] *= enorm
    return fb


_FB = _mel_filterbank()


def log_mel(pcm: np.ndarray) -> np.ndarray:
    """Log-mel NON normalise, (80, T)."""
    x = np.empty_like(pcm)
    x[0] = pcm[0]
    x[1:] = pcm[1:] - PREEMPH * pcm[:-1]
    pad = N_FFT // 2
    xp = np.pad(x, (pad, pad), mode="reflect")
    n_frames = 1 + (len(xp) - N_FFT) // HOP
    win = np.hanning(WIN + 1)[:-1]
    win_pad = (N_FFT - WIN) // 2
    frames = np.zeros((n_frames, N_FFT))
    for t in range(n_frames):
        start = t * HOP
        seg = xp[start + win_pad: start + win_pad + WIN]
        frames[t, win_pad: win_pad + WIN] = seg * win
    spec = np.abs(np.fft.rfft(frames, n=N_FFT, axis=1)) ** 2
    mel = _FB @ spec.T  # (80, T)
    return np.log(mel + 2.0 ** -24)


def normalize_per_feature(lm: np.ndarray) -> np.ndarray:
    mean = lm.mean(axis=1, keepdims=True)
    std = lm.std(axis=1, ddof=1, keepdims=True) + NORM_EPS
    return (lm - mean) / std


def normalize_fixed(lm: np.ndarray, mean: np.ndarray, std: np.ndarray) -> np.ndarray:
    return (lm - mean[:, None]) / std[:, None]


# ── Decode CTC greedy ────────────────────────────────────────────────────────
with open(VOCAB, encoding="utf-8") as f:
    PIECES = json.load(f)
BLANK = len(PIECES)


def decode(logprobs: np.ndarray) -> str:
    ids = logprobs.argmax(axis=-1)
    out, prev = [], -1
    for i in ids:
        if i != prev and i != BLANK:
            out.append(PIECES[i])
        prev = i
    return "".join(out).replace("▁", " ").strip()


def wer(ref: str, hyp: str) -> float:
    r, h = ref.split(), hyp.split()
    d = np.zeros((len(r) + 1, len(h) + 1), dtype=int)
    d[:, 0] = np.arange(len(r) + 1)
    d[0, :] = np.arange(len(h) + 1)
    for i in range(1, len(r) + 1):
        for j in range(1, len(h) + 1):
            d[i, j] = min(d[i - 1, j] + 1, d[i, j - 1] + 1,
                          d[i - 1, j - 1] + (r[i - 1] != h[j - 1]))
    return d[len(r), len(h)] / max(1, len(r))


def transcribe(sess, feats: np.ndarray) -> str:
    T = feats.shape[1]
    out = sess.run(None, {
        "audio_signal": feats[None].astype(np.float32),
        "length": np.array([T], dtype=np.int64),
    })
    return decode(out[0][0])


def main():
    random.seed(0)
    sess = ort.InferenceSession(str(ONNX), providers=["CPUExecutionProvider"])

    # 1. Stats fixes sur le corpus d'entrainement
    train = [json.loads(l) for l in open(TRAIN_MANIFEST, encoding="utf-8")]
    sample = random.sample(train, N_STATS_CLIPS)
    s0 = np.zeros(N_MELS)
    s1 = np.zeros(N_MELS)
    n_frames_tot = 0
    for e in sample:
        pcm, _ = sf.read(e["audio_filepath"], dtype="float32")
        lm = log_mel(pcm)
        s0 += lm.sum(axis=1)
        s1 += (lm ** 2).sum(axis=1)
        n_frames_tot += lm.shape[1]
    mean = s0 / n_frames_tot
    std = np.sqrt(s1 / n_frames_tot - mean ** 2) + NORM_EPS
    STATS_OUT.write_text(json.dumps({
        "mean": mean.tolist(), "std": std.tolist(),
        "n_clips": N_STATS_CLIPS, "n_frames": int(n_frames_tot),
    }), encoding="utf-8")
    print(f"[1] Stats fixes estimees sur {N_STATS_CLIPS} clips "
          f"({n_frames_tot} frames) -> {STATS_OUT.name}")

    # 2. WER clips isoles
    val = [json.loads(l) for l in open(VAL_MANIFEST, encoding="utf-8")]
    eval_clips = random.sample(val, N_EVAL_CLIPS)
    wers_pf, wers_fx = [], []
    for e in eval_clips:
        pcm, _ = sf.read(e["audio_filepath"], dtype="float32")
        lm = log_mel(pcm)
        wers_pf.append(wer(e["text"], transcribe(sess, normalize_per_feature(lm))))
        wers_fx.append(wer(e["text"], transcribe(sess, normalize_fixed(lm, mean, std))))
    print(f"[2] Clips isoles (n={N_EVAL_CLIPS}) : "
          f"per_feature WER={np.mean(wers_pf)*100:.2f}% | "
          f"stats fixes WER={np.mean(wers_fx)*100:.2f}%")

    # 3. Sessions concatenees : WER du DERNIER TIERS des versets de la session
    sil = np.zeros(int(SILENCE_S * SR), dtype=np.float32)
    tail_pf, tail_fx = [], []
    for _ in range(N_SESSIONS):
        verses = random.sample(val, VERSES_PER_SESSION)
        pcms = []
        for e in verses:
            pcm, _ = sf.read(e["audio_filepath"], dtype="float32")
            pcms.append(pcm)
            pcms.append(sil)
        full = np.concatenate(pcms[:-1])
        ref_full = " ".join(e["text"] for e in verses)
        # reference du dernier tiers (les versets les plus exposes a la derive)
        k = VERSES_PER_SESSION - VERSES_PER_SESSION // 3
        ref_tail = " ".join(e["text"] for e in verses[k:])
        lm = log_mel(full)
        hyp_pf = transcribe(sess, normalize_per_feature(lm))
        hyp_fx = transcribe(sess, normalize_fixed(lm, mean, std))
        # WER de fin de session : approximation par alignement du suffixe
        n_tail_words = len(ref_tail.split())
        tail_pf.append(wer(ref_tail, " ".join(hyp_pf.split()[-n_tail_words:])))
        tail_fx.append(wer(ref_tail, " ".join(hyp_fx.split()[-n_tail_words:])))
        # trace complete pour inspection
        print(f"    session: full_wer pf={wer(ref_full, hyp_pf)*100:.1f}% "
              f"fx={wer(ref_full, hyp_fx)*100:.1f}% | "
              f"tail pf={tail_pf[-1]*100:.1f}% fx={tail_fx[-1]*100:.1f}%")
    print(f"[3] Fin de session (~{SILENCE_S}s silence, {VERSES_PER_SESSION} versets, "
          f"n={N_SESSIONS}) : per_feature tail-WER={np.mean(tail_pf)*100:.2f}% | "
          f"stats fixes tail-WER={np.mean(tail_fx)*100:.2f}%")

    print("\nCritere : adopter les stats fixes si [2] fixe <= per_feature+0.5pt "
          "ET [3] fixe nettement meilleur.")


if __name__ == "__main__":
    main()
