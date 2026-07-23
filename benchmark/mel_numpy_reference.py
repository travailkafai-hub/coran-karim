"""
Reimplementation pure numpy (sans NeMo/torch) du calcul mel-spectrogramme exact
utilise par nvidia/stt_ar_fastconformer_hybrid_large_pcd_v1.0 (AudioToMelSpectrogramPreprocessor).

Sert de REFERENCE pour le portage natif Android (Kotlin/C++) : on valide d'abord
que cette version numpy pure colle bit-pres a la sortie NeMo, puis on porte cet
algorithme (deja verifie) en natif -- au lieu de porter directement depuis le
code PyTorch (plus risque de subtils ecarts).

Parametres (extraits de model.cfg.preprocessor, verifies dans features.py) :
  sample_rate=16000, n_fft=512, win_length=400 (25ms), hop_length=160 (10ms)
  window=hann (periodic=False), preemph=0.97, n_mels=80, fmin=0, fmax=8000
  mel_norm="slaney" (defaut librosa), mag_power=2.0 (spectre de puissance)
  log: log(mel + 2**-24), normalize="per_feature" (par bin mel, ddof=1, +1e-5)
  center=True, pad_mode="constant" (zero-padding, PAS reflect)
"""
import numpy as np


def hann_window_periodic_false(n: int) -> np.ndarray:
    """torch.hann_window(n, periodic=False) == fenetre symetrique standard."""
    if n == 1:
        return np.ones(1, dtype=np.float64)
    k = np.arange(n)
    return 0.5 - 0.5 * np.cos(2 * np.pi * k / (n - 1))


def mel_filterbank_slaney(sr=16000, n_fft=512, n_mels=80, fmin=0.0, fmax=8000.0) -> np.ndarray:
    """Reimplementation de librosa.filters.mel(norm='slaney') sans dependance a librosa,
    pour que le portage natif n'ait pas besoin de librosa non plus."""
    n_freqs = n_fft // 2 + 1
    fft_freqs = np.linspace(0, sr / 2, n_freqs)

    def hz_to_mel(f):
        f = np.asarray(f, dtype=np.float64)
        f_min, f_sp = 0.0, 200.0 / 3
        mel = (f - f_min) / f_sp
        min_log_hz = 1000.0
        min_log_mel = (min_log_hz - f_min) / f_sp
        logstep = np.log(6.4) / 27.0
        is_log = f >= min_log_hz
        mel = np.where(is_log, min_log_mel + np.log(np.maximum(f, 1e-10) / min_log_hz) / logstep, mel)
        return mel

    def mel_to_hz(m):
        m = np.asarray(m, dtype=np.float64)
        f_min, f_sp = 0.0, 200.0 / 3
        f = f_min + f_sp * m
        min_log_hz = 1000.0
        min_log_mel = (min_log_hz - f_min) / f_sp
        logstep = np.log(6.4) / 27.0
        is_log = m >= min_log_mel
        f = np.where(is_log, min_log_hz * np.exp(logstep * (m - min_log_mel)), f)
        return f

    min_mel = hz_to_mel(fmin)
    max_mel = hz_to_mel(fmax)
    mel_pts = np.linspace(min_mel, max_mel, n_mels + 2)
    hz_pts = mel_to_hz(mel_pts)

    fb = np.zeros((n_mels, n_freqs), dtype=np.float64)
    fdiff = np.diff(hz_pts)
    ramps = hz_pts.reshape(-1, 1) - fft_freqs.reshape(1, -1)
    for i in range(n_mels):
        lower = -ramps[i] / fdiff[i]
        upper = ramps[i + 2] / fdiff[i + 1]
        fb[i] = np.maximum(0, np.minimum(lower, upper))

    # Normalisation "slaney" : aire de chaque filtre triangulaire = 1 (comme librosa norm='slaney')
    enorm = 2.0 / (hz_pts[2:n_mels + 2] - hz_pts[:n_mels])
    fb *= enorm[:, np.newaxis]
    return fb.astype(np.float32)


def compute_mel_features(audio: np.ndarray, sr=16000, n_fft=512, win_length=400,
                          hop_length=160, n_mels=80, preemph=0.97,
                          log_zero_guard=2.0 ** -24, norm_eps=1e-5,
                          normalize="per_feature") -> np.ndarray:
    """Reproduit AudioToMelSpectrogramPreprocessor(pcd).forward() en eval mode
    (dither desactive car self.training=False dans NeMo).
    Retourne (n_mels, T) deja log + normalise par-feature (mean/std, ddof=1).

    `normalize` (ajout 2026-07-23, le defaut "per_feature" ne change RIEN au
    comportement historique valide bit-exact contre NeMo) :
      "per_feature"   mean/std recalcules sur CE buffer (comportement NeMo/Kotlin)
      None            log-mel BRUT, non normalise (sert a calculer des stats fixes)
      (mean, std)     stats FIXES imposees, shape (n_mels,1) ou (n_mels,)
    Motivation : la normalisation per_feature derive quand le buffer grossit ou
    se remplit de silence -- cause mesuree de l'effondrement des transcriptions
    sur device (cf. BufferedTranscriber header v2/v3 et le test
    test_norm_fixed_vs_perfeature.py). Ce parametre permet de MESURER
    l'alternative "stats fixes" sans toucher au chemin par defaut."""
    audio = audio.astype(np.float64)

    # 1) Preemphasis
    x = np.empty_like(audio)
    x[0] = audio[0]
    x[1:] = audio[1:] - preemph * audio[:-1]

    # 2) Zero-pad centre (torch.stft center=True, pad_mode="constant")
    pad = n_fft // 2
    x_padded = np.pad(x, (pad, pad), mode="constant")

    # 3) Framing + fenetre Hann (win_length=400), puis zero-pad centre a n_fft=512
    window = hann_window_periodic_false(win_length)
    n_frames = 1 + (len(x_padded) - n_fft) // hop_length
    frames = np.zeros((n_frames, n_fft), dtype=np.float64)
    win_pad = (n_fft - win_length) // 2
    # Chaque frame couvre n_fft echantillons [t*hop, t*hop+n_fft) du signal pad ;
    # seule la portion CENTREE de win_length echantillons est ponderee par la fenetre
    # (le reste de la frame n_fft est implicitement a zero) -- torch.stft centre la
    # fenetre win_length<n_fft de cette maniere, ce n'est PAS un simple x[start:start+win_length].
    for t in range(n_frames):
        start = t * hop_length
        seg = x_padded[start + win_pad:start + win_pad + win_length]
        frames[t, win_pad:win_pad + win_length] = seg * window

    # 4) FFT reelle -> magnitude -> puissance (mag_power=2.0)
    spec = np.fft.rfft(frames, n=n_fft, axis=1)          # (T, n_fft//2+1)
    power = (np.abs(spec) ** 2).astype(np.float64)        # magnitude^2 == power directement

    # 5) Filterbank mel (slaney) : (n_mels, n_freqs) @ (n_freqs, T) -> (n_mels, T)
    fb = mel_filterbank_slaney(sr=sr, n_fft=n_fft, n_mels=n_mels)
    mel = fb.astype(np.float64) @ power.T                  # (n_mels, T)

    # 6) log
    log_mel = np.log(mel + log_zero_guard)

    # 7) Normalisation per_feature (par bin mel, ddof=1) + epsilon
    if normalize is None:
        return log_mel.astype(np.float32)  # brut, pour calculer des stats fixes
    if normalize != "per_feature":
        mean, std = normalize
        mean = np.asarray(mean, dtype=np.float64).reshape(n_mels, 1)
        std = np.asarray(std, dtype=np.float64).reshape(n_mels, 1) + norm_eps
        return ((log_mel - mean) / std).astype(np.float32)
    mean = log_mel.mean(axis=1, keepdims=True)
    std = log_mel.std(axis=1, ddof=1, keepdims=True)
    std = std + norm_eps
    normalized = (log_mel - mean) / std

    return normalized.astype(np.float32)  # (n_mels, T)
