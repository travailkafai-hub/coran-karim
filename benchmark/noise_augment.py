"""
Noise augmentation utilities for Quran ASR training.

Priority:
  1. Real recorded clips from data/ambient_noise/ (manifest_ambient.jsonl)
  2. Synthetic generators as fallback when no real clips available

Noise types (synthetic):
  white   — broadband gaussian (TV static, fan)
  pink    — 1/f spectrum (general ambiance)
  hum     — 50Hz + harmonics (AC unit, fridge)
  crowd   — filtered pink noise bursts (babble)
  traffic — low-pass gaussian (street noise below 800 Hz)

All functions work on float32 numpy arrays at 16kHz.
"""
import os, json
import numpy as np
import soundfile as sf

RNG = np.random.default_rng()

# ── Real noise clips (loaded once at first call) ──────────────────────────────

_real_clips: list[np.ndarray] | None = None   # None = not yet loaded

def _load_real_clips() -> list[np.ndarray]:
    """Load recorded ambient noise WAVs from manifest_ambient.jsonl (once)."""
    global _real_clips
    if _real_clips is not None:
        return _real_clips

    root = os.path.dirname(os.path.abspath(__file__))
    manifest = os.path.join(root, "data", "manifest_ambient.jsonl")
    clips = []

    if os.path.exists(manifest):
        for line in open(manifest, encoding="utf-8"):
            try:
                row = json.loads(line)
                path = os.path.join(root, row["audio"])
                if os.path.exists(path):
                    audio, sr_file = sf.read(path, dtype="float32")
                    if audio.ndim > 1:
                        audio = audio.mean(axis=1)          # stereo → mono
                    if sr_file != 16000:
                        # Simple integer decimation / repetition
                        # (for proper resampling install librosa or resampy)
                        ratio = 16000 / sr_file
                        new_len = int(len(audio) * ratio)
                        audio = np.interp(
                            np.linspace(0, len(audio) - 1, new_len),
                            np.arange(len(audio)), audio,
                        ).astype(np.float32)
                    clips.append(audio)
            except Exception:
                pass

        if clips:
            print(f"[noise_augment] {len(clips)} real ambient clips loaded "
                  f"from {manifest}", flush=True)
        else:
            print(f"[noise_augment] manifest_ambient.jsonl found but no valid "
                  f"clips. Using synthetic noise only.", flush=True)
    else:
        print(f"[noise_augment] No real clips (run record_ambient_noise.py). "
              f"Using synthetic noise.", flush=True)

    _real_clips = clips
    return clips


# ── Core mixing ───────────────────────────────────────────────────────────────

def _rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(x ** 2)) + 1e-9)


def mix_at_snr(clean: np.ndarray, noise: np.ndarray, snr_db: float) -> np.ndarray:
    """Mix noise into clean so the resulting SNR = snr_db dB."""
    noise = _match_length(noise, len(clean))
    target_rms = _rms(clean) / (10 ** (snr_db / 20.0))
    noise = noise / (_rms(noise) + 1e-9) * target_rms
    out = clean + noise
    peak = np.max(np.abs(out))
    if peak > 0.98:
        out = out / peak * 0.98
    return out.astype(np.float32)


def _match_length(noise: np.ndarray, n: int) -> np.ndarray:
    if len(noise) >= n:
        start = RNG.integers(0, len(noise) - n + 1)
        return noise[start : start + n]
    reps = n // len(noise) + 2
    long = np.tile(noise, reps)
    start = RNG.integers(0, len(long) - n + 1)
    return long[start : start + n]


# ── Synthetic generators ──────────────────────────────────────────────────────

def white_noise(n: int, sr: int = 16000) -> np.ndarray:
    return RNG.standard_normal(n).astype(np.float32)


def pink_noise(n: int, sr: int = 16000) -> np.ndarray:
    """1/f spectrum via spectral shaping of white noise."""
    f = np.fft.rfftfreq(n)
    f[0] = 1.0
    spectrum = 1.0 / np.sqrt(f)
    white = (RNG.standard_normal(n // 2 + 1) +
             1j * RNG.standard_normal(n // 2 + 1))
    out = np.fft.irfft(white * spectrum, n).astype(np.float32)
    return out / (np.max(np.abs(out)) + 1e-9)


def hum_noise(n: int, sr: int = 16000) -> np.ndarray:
    """50 Hz mains hum + harmonics (AC unit, fridge, fluorescent light)."""
    t = np.arange(n, dtype=np.float32) / sr
    out = np.zeros(n, dtype=np.float32)
    for k, amp in [(1, 1.0), (2, 0.4), (3, 0.2), (5, 0.1), (7, 0.05)]:
        phase = RNG.uniform(0, 2 * np.pi)
        out += amp * np.sin(2 * np.pi * 50 * k * t + phase)
    return out / (np.max(np.abs(out)) + 1e-9)


def crowd_noise(n: int, sr: int = 16000) -> np.ndarray:
    """Babble / crowd — amplitude-modulated pink noise."""
    base = pink_noise(n, sr)
    t = np.arange(n, dtype=np.float32) / sr
    mod_freq = RNG.uniform(0.5, 3.0)
    mod = 0.6 + 0.4 * np.sin(
        2 * np.pi * mod_freq * t + RNG.uniform(0, 2 * np.pi))
    return (base * mod).astype(np.float32)


def traffic_noise(n: int, sr: int = 16000) -> np.ndarray:
    """Street traffic — low-pass gaussian (dominant energy below 800 Hz)."""
    raw = RNG.standard_normal(n).astype(np.float32)
    alpha = 1.0 - np.exp(-2 * np.pi * (800.0 / sr))
    out = np.zeros(n, dtype=np.float32)
    state = 0.0
    for i in range(n):
        state = state + alpha * (raw[i] - state)
        out[i] = state
    return out / (np.max(np.abs(out)) + 1e-9)


_SYNTHETIC = {
    "white":   white_noise,
    "pink":    pink_noise,
    "hum":     hum_noise,
    "crowd":   crowd_noise,
    "traffic": traffic_noise,
}
_SYNTH_KEYS = list(_SYNTHETIC.keys())


# ── Public API ────────────────────────────────────────────────────────────────

def _sample_noise(n: int, sr: int, real_prob: float = 0.6) -> np.ndarray:
    """
    Draw one noise sample:
      - With probability `real_prob`: pick a real recorded clip (if any)
      - Otherwise: generate synthetic noise

    real_prob=0.6 means 60 % of augmentations use real mic recordings when
    available, 40 % use synthetic generators (covers cases not in recordings).
    """
    real_clips = _load_real_clips()

    use_real = real_clips and RNG.random() < real_prob
    if use_real:
        clip = real_clips[RNG.integers(len(real_clips))]
        return _match_length(clip, n)
    else:
        key = _SYNTH_KEYS[RNG.integers(len(_SYNTH_KEYS))]
        return _SYNTHETIC[key](n, sr)


def random_augment(
    audio: np.ndarray,
    sr: int = 16000,
    prob: float = 0.4,
    snr_range_db: tuple[float, float] = (5.0, 20.0),
    real_noise_prob: float = 0.6,
) -> np.ndarray:
    """
    Apply random noise augmentation with probability `prob`.

    Args:
        audio          : clean float32 audio at `sr` Hz
        sr             : sample rate (default 16000)
        prob           : probability of applying augmentation (0–1)
        snr_range_db   : (min, max) SNR in dB — lower = noisier
        real_noise_prob: fraction of augmentations that use real recorded clips
                         (remainder use synthetic generators)

    Returns the original array unchanged when the random draw fails.
    """
    if RNG.random() > prob:
        return audio
    noise = _sample_noise(len(audio), sr, real_noise_prob)
    snr   = float(RNG.uniform(snr_range_db[0], snr_range_db[1]))
    return mix_at_snr(audio, noise, snr)
