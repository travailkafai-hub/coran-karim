"""Rejoue les WAV captés SUR LE TÉLÉPHONE à travers plusieurs modèles ONNX et
compare les transcriptions libres, mot pour mot.

POURQUOI (2026-07-25, demande utilisateur) : sur device, les transcriptions du
modèle DEUX TÊTES déployé se sont dégradées de façon spectaculaire à partir de
segments de 4-6 s ("مِ ٱللَّهِ ٱلرَّحْمَحِيمِ", "هُ", "ذَٰلِكَ ٱلْكِتَ فِيهِ حَكِيلَمِينَ"),
là où la même récitation en segments de 2-3 s donnait un texte propre. Deux
explications possibles, qu'aucun log ne permet de distinguer :
  H1. La chaîne de l'app (segmentation, buffer, longueur des segments) prive le
      modèle d'un contexte exploitable -> le modèle n'y est pour rien.
  H2. Le modèle deux têtes lui-même transcrit moins bien que le meilleur modèle
      UNE tête de l'historique -> régression du modèle.

Ce banc tranche : MÊME audio (celui du téléphone, pas un clip de studio), MÊME
mel, MÊME décodage glouton, seul le modèle change.

⚠️ POINT DE MÉTHODE ESSENTIEL : le mel est recalculé ici avec EXACTEMENT les
paramètres de `MelSpectrogram.kt` (le code qui tourne sur le téléphone), pas
avec le préprocesseur NeMo. C'est volontaire : on veut savoir ce que le modèle
reçoit RÉELLEMENT dans l'app, pas ce qu'il recevrait dans un banc idéal. Toute
divergence entre les deux serait elle-même un bug à traiter séparément.
Paramètres (cf. MelSpectrogram.kt en-tête) : 16 kHz, n_fft=512, win=400,
hop=160, hann(periodic=false), preemph=0.97, n_mels=80, fmin=0, fmax=8000,
mel_norm=slaney, mag_power=2.0, log(x + 2^-24), normalisation per_feature
(ddof=1, +1e-5).

USAGE
    PYTHONPATH="benchmark/.venv_nemo/lib/python3.14/site-packages" \
      /usr/bin/python3.14 benchmark/compare_onnx_on_device_wavs.py <dossier_wav>

    Optionnel : --models nom1=chemin1 nom2=chemin2 ...
    Par défaut compare le modèle déployé sur le téléphone (deux têtes) au
    meilleur modèle UNE tête de l'historique (mixed-e02 = epoch 14 du run
    tajweed-mixed, cf. CLAUDE.md).
"""
import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np
import onnxruntime as ort

BASE = Path(__file__).parent

# ── Paramètres du mel : COPIE de MelSpectrogram.kt (ne pas "améliorer") ──────
SAMPLE_RATE = 16000
N_FFT = 512
WIN_LENGTH = 400
HOP_LENGTH = 160
N_MELS = 80
PREEMPH = 0.97
LOG_ZERO_GUARD = 2.0 ** -24
WIN_PAD = (N_FFT - WIN_LENGTH) // 2

DEFAULT_MODELS = {
    # Ce que le téléphone exécute aujourd'hui (2 têtes : lettres + tajwid).
    "2tetes-multilabel-v3": BASE
    / "models/fastconformer-dual-head-v1/deploy/fastconformer-ctc-dual-head-multilabel-v3",
    # Référence historique 1 tête. Nom de dossier trompeur ("e02") : le contenu
    # réel est l'EPOCH 14 du run tajweed-mixed (cf. CLAUDE.md §modèle déployé).
    "1tete-mixed-e14": BASE / "models_deployes/fastconformer-ctc-mixed-e02",
}


def hann_periodic_false(n: int) -> np.ndarray:
    """hann(periodic=false) = symétrique, dénominateur n-1 (cf. Kotlin)."""
    return np.array([0.5 - 0.5 * math.cos(2.0 * math.pi * i / (n - 1)) for i in range(n)])


def hz_to_mel(f: float) -> float:
    """Échelle mel Slaney (linéaire sous 1 kHz, log au-dessus) — celle de NeMo."""
    f_min, f_sp = 0.0, 200.0 / 3
    mel = (f - f_min) / f_sp
    min_log_hz, min_log_mel = 1000.0, (1000.0 - f_min) / f_sp
    logstep = math.log(6.4) / 27.0
    if f >= min_log_hz:
        mel = min_log_mel + math.log(f / min_log_hz) / logstep
    return mel


def mel_to_hz(m: float) -> float:
    f_min, f_sp = 0.0, 200.0 / 3
    f = f_min + f_sp * m
    min_log_hz, min_log_mel = 1000.0, (1000.0 - f_min) / f_sp
    logstep = math.log(6.4) / 27.0
    if m >= min_log_mel:
        f = min_log_hz * math.exp(logstep * (m - min_log_mel))
    return f


def build_filterbank() -> np.ndarray:
    n_freqs = N_FFT // 2 + 1
    fft_freqs = np.array([i * (SAMPLE_RATE / 2.0) / (n_freqs - 1) for i in range(n_freqs)])
    min_mel, max_mel = hz_to_mel(0.0), hz_to_mel(8000.0)
    mel_pts = np.array([min_mel + i * (max_mel - min_mel) / (N_MELS + 1) for i in range(N_MELS + 2)])
    hz_pts = np.array([mel_to_hz(m) for m in mel_pts])
    fdiff = np.diff(hz_pts)
    fb = np.zeros((N_MELS, n_freqs))
    for i in range(N_MELS):
        lower = (fft_freqs - hz_pts[i]) / fdiff[i]
        upper = (hz_pts[i + 2] - fft_freqs) / fdiff[i + 1]
        fb[i] = np.maximum(0.0, np.minimum(lower, upper))
        # Normalisation slaney : aire unitaire par filtre.
        fb[i] *= 2.0 / (hz_pts[i + 2] - hz_pts[i])
    return fb


FILTERBANK = build_filterbank()
WINDOW = hann_periodic_false(WIN_LENGTH)


def read_wav_mono16k(path: Path) -> np.ndarray:
    """Lit un WAV PCM16 mono 16 kHz (ce qu'écrit WavWriter.kt) sans dépendance."""
    import wave

    with wave.open(str(path), "rb") as w:
        assert w.getnchannels() == 1, f"{path}: pas mono"
        assert w.getsampwidth() == 2, f"{path}: pas PCM16"
        assert w.getframerate() == SAMPLE_RATE, f"{path}: {w.getframerate()} Hz"
        raw = w.readframes(w.getnframes())
    return np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0


def mel_spectrogram(samples: np.ndarray) -> np.ndarray:
    """(80, T) — reproduction fidèle de MelSpectrogram.kt."""
    # Pré-emphase, puis padding centré (reflect) comme le préprocesseur NeMo.
    pre = np.empty_like(samples)
    pre[0] = samples[0]
    pre[1:] = samples[1:] - PREEMPH * samples[:-1]
    padded = np.pad(pre, (N_FFT // 2, N_FFT // 2), mode="reflect")

    n_frames = 1 + (len(pre)) // HOP_LENGTH
    out = np.zeros((N_MELS, n_frames), dtype=np.float32)
    for t in range(n_frames):
        start = t * HOP_LENGTH
        frame = np.zeros(N_FFT)
        seg = padded[start + WIN_PAD : start + WIN_PAD + WIN_LENGTH]
        if len(seg) < WIN_LENGTH:
            seg = np.pad(seg, (0, WIN_LENGTH - len(seg)))
        frame[WIN_PAD : WIN_PAD + WIN_LENGTH] = seg * WINDOW
        spec = np.abs(np.fft.rfft(frame)) ** 2.0  # mag_power=2.0
        out[:, t] = np.log(FILTERBANK @ spec + LOG_ZERO_GUARD)

    # Normalisation per_feature (ddof=1, +1e-5) — cf. Kotlin/NeMo.
    mean = out.mean(axis=1, keepdims=True)
    std = out.std(axis=1, ddof=1, keepdims=True)
    return (out - mean) / (std + 1e-5)


def load_vocab(model_dir: Path) -> list[str]:
    v = json.loads((model_dir / "vocab.json").read_text(encoding="utf-8"))
    if isinstance(v, dict):
        # {"pieces": [...]} ou {token: id}
        if "pieces" in v:
            return v["pieces"]
        return [t for t, _ in sorted(v.items(), key=lambda kv: kv[1])]
    return v


def greedy_decode(logprobs: np.ndarray, vocab: list[str], blank: int) -> str:
    """CTC glouton + fusion des répétitions — même règle que le Kotlin."""
    ids = logprobs.argmax(axis=-1)
    out, prev = [], -1
    for i in ids:
        if i != prev and i != blank:
            out.append(vocab[i] if i < len(vocab) else "")
        prev = i
    return "".join(out).replace("▁", " ").strip()


def strip_private_use(s: str) -> str:
    """Retire les symboles de règles tajwid (zone privée Unicode) — ils n'ont
    pas de glyphe et polluent la comparaison textuelle."""
    return "".join(c for c in s if not (0xE000 <= ord(c) <= 0xF8FF))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("wav_dir", type=Path)
    ap.add_argument("--models", nargs="*", default=None,
                    help="nom=chemin_dossier (contenant model.onnx + vocab.json)")
    args = ap.parse_args()

    models = dict(DEFAULT_MODELS)
    if args.models:
        models = {}
        for spec in args.models:
            name, _, path = spec.partition("=")
            models[name] = Path(path)

    sessions = {}
    for name, d in models.items():
        onnx = d / "model.onnx"
        if not onnx.exists():
            print(f"⚠️  {name}: {onnx} absent — ignoré")
            continue
        so = ort.SessionOptions()
        so.log_severity_level = 3
        sess = ort.InferenceSession(str(onnx), so, providers=["CPUExecutionProvider"])
        names = [i.name for i in sess.get_inputs()]
        assert "audio_signal" in names, (
            f"{name}: entrées={names} — export inutilisable par l'app "
            f"(cf. CLAUDE.md, piège 'audio_signal vs raw_audio')")
        vocab = load_vocab(d)
        blank = len(vocab)  # convention NeMo : blank = dernier index
        sessions[name] = (sess, vocab, blank, len(sess.get_outputs()))
        print(f"✓ {name}: {len(vocab)} tokens, {len(sess.get_outputs())} sortie(s)")

    if not sessions:
        print("Aucun modèle chargeable.")
        return 1

    wavs = sorted(args.wav_dir.glob("*.wav"))
    if not wavs:
        print(f"Aucun WAV dans {args.wav_dir}")
        return 1
    print(f"\n{len(wavs)} clips à comparer\n" + "=" * 78)

    for w in wavs:
        samples = read_wav_mono16k(w)
        dur = len(samples) / SAMPLE_RATE
        mel = mel_spectrogram(samples)[None, :, :]  # (1, 80, T)
        length = np.array([mel.shape[2]], dtype=np.int64)
        print(f"\n{w.name}  ({dur:.2f}s, {mel.shape[2]} frames)")
        for name, (sess, vocab, blank, n_out) in sessions.items():
            outs = sess.run(None, {"audio_signal": mel.astype(np.float32), "length": length})
            text = greedy_decode(outs[0][0], vocab, blank)
            print(f"   {name:24s} : {strip_private_use(text)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
