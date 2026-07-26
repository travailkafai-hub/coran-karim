"""Rejoue le streaming causal HORS DEVICE en faisant varier la SEULE politique
de normalisation, pour trancher la derive mesuree sur device le 2026-07-26.

CE QU'ON A MESURE SUR DEVICE (log 16:14:38 -> 16:15:21, 43,5 s de recitation
reelle) : la chaine suit parfaitement pendant 25 s (mots 4 a 19 valides, ancre
8 -> 20), puis PLUS RIEN pendant 18 s -- les blocs PCM arrivent toujours,
l'inference tourne toujours, mais aucun mot n'est plus confirme. Donc ni
orange, ni rouge, ni correction : le curseur gele en silence.

CAUSE IDENTIFIEE dans FastConformerStreamingSession.kt : les statistiques de
normalisation sont CUMULEES SUR TOUTE LA SESSION, sans fenetre ni remise a
zero (`statSum[m] += lm[m]` ... `mean[m] = statSum[m] / statCount`). C'est la
derive de normalisation deja documentee en tete de BufferedTranscriber.kt,
reintroduite ici. Le modele a ete entraine avec une normalisation PAR CLIP
(<= 20 s) ; apres ~25-30 s de session, et surtout apres des silences qui
tirent la moyenne vers le bas, les features sortent de la distribution
d'entrainement et le CTC n'emet plus que du blank.

POURQUOI CE BANC AVANT DE TOUCHER AU KOTLIN (regle CLAUDE.md : « toucher a la
segmentation sans mesure prealable hors device = perte de temps garantie » --
quatre correctifs « evidents » y ont deja ete rejetes par la mesure) :
l'EFFET DE BORD que la fenetre glissante introduit n'est pas evident. Le cache
causal contient des encodages calcules avec les ANCIENNES statistiques alors
que les nouvelles frames utiliseraient les NOUVELLES. Cette incoherence peut
degrader l'encodeur a chaque changement de fenetre. Ce banc la mesure au lieu
de la supposer.

Reproduit fidelement la boucle Kotlin (`feedAudio`) :
  - pre-emphase puis log-mel frame par frame, HOP=160, causal strict
  - fenetre d'entree de `input_frames`, inference tous les `shift_frames`
  - cache_last_channel / cache_last_time propages d'un appel au suivant
  - seules `valid_output_frames` frames de sortie sont conservees
Seule la NORMALISATION change d'une politique a l'autre.

USAGE
    PYTHONPATH=benchmark/.venv_nemo/lib/python3.14/site-packages \
      /usr/bin/python3.14 benchmark/bench_causal_normalization.py <fichier.wav>
"""
import argparse
import json
import sys
import wave
from pathlib import Path

import numpy as np
import onnxruntime as ort

sys.path.insert(0, str(Path(__file__).parent))
from mel_numpy_reference import (  # noqa: E402
    hann_window_periodic_false, mel_filterbank_slaney)

BASE = Path(__file__).parent
import os
DEPLOY = Path(os.environ.get("CAUSAL_DEPLOY",
    str(BASE / "models/fastconformer-streaming-causal-v1-lr3e4/deploy/fastconformer-ctc-causal-v1")))
N_FFT = 512
WIN_LENGTH = 400
HOP_LENGTH = 160
WINDOW = hann_window_periodic_false(WIN_LENGTH)
FILTERBANK = mel_filterbank_slaney()
PREEMPH = 0.97
LOG_GUARD = 2.0 ** -24
N_MELS = 80
NORM_EPS = 1e-5


def read_wav(path):
    with wave.open(str(path), "rb") as w:
        assert w.getframerate() == 16000 and w.getnchannels() == 1
        raw = w.readframes(w.getnframes())
    return np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0


def log_mel_frames(samples):
    """Toutes les frames log-mel (AVANT normalisation) -- equivalent de
    MelSpectrogram.frameLogMel appele en boucle cote Kotlin."""
    pre = np.empty_like(samples)
    pre[0] = samples[0]
    pre[1:] = samples[1:] - PREEMPH * samples[:-1]
    pad = N_FFT // 2
    padded = np.pad(pre, (pad, pad), mode="reflect")
    n = 1 + (len(pre)) // HOP_LENGTH
    out = np.empty((n, N_MELS), dtype=np.float64)
    win_pad = (N_FFT - len(WINDOW)) // 2
    for t in range(n):
        frame = np.zeros(N_FFT)
        seg = padded[t * HOP_LENGTH + win_pad: t * HOP_LENGTH + win_pad + len(WINDOW)]
        if len(seg) < len(WINDOW):
            seg = np.pad(seg, (0, len(WINDOW) - len(seg)))
        frame[win_pad: win_pad + len(WINDOW)] = seg * WINDOW
        spec = np.abs(np.fft.rfft(frame)) ** 2.0
        out[t] = np.log(FILTERBANK @ spec + LOG_GUARD)
    return out


def normalize(mels, upto, policy, window_frames):
    """mean/std appliques a la fenetre d'entree, selon [policy].

    cumulative  : tout depuis le debut de session -- CE QUI TOURNE AUJOURD'HUI
    sliding     : les `window_frames` dernieres frames seulement
    """
    if policy == "cumulative":
        hist = mels[:upto]
    else:
        hist = mels[max(0, upto - window_frames):upto]
    mean = hist.mean(axis=0)
    std = hist.std(axis=0, ddof=1) + NORM_EPS if len(hist) > 1 else np.ones(N_MELS)
    return mean, std


def run(mels, cfg, sess, vocab, policy, window_frames):
    inp, shift = cfg["input_frames"], cfg["shift_frames"]
    valid = cfg["valid_output_frames"]
    cache_ch = np.zeros(cfg["cache_last_channel_shape"], dtype=np.float32)
    cache_t = np.zeros(cfg["cache_last_time_shape"], dtype=np.float32)
    cache_len = np.array([0], dtype=np.int64)

    ids, timeline = [], []
    next_end = inp
    while next_end <= len(mels):
        mean, std = normalize(mels, next_end, policy, window_frames)
        win = mels[max(0, next_end - inp):next_end]
        if len(win) < inp:  # premiere fenetre : complete a GAUCHE par des zeros
            win = np.vstack([np.zeros((inp - len(win), N_MELS)), win])
        feats = ((win - mean) / std).T.astype(np.float32)[None]
        out = sess.run(None, {
            "audio_signal": feats,
            "length": np.array([inp], dtype=np.int64),
            "cache_last_channel": cache_ch,
            "cache_last_time": cache_t,
            "cache_last_channel_len": cache_len,
        })
        lp, cache_ch, cache_t, cache_len = out[0], out[1], out[2], out[3]
        blank = lp.shape[-1] - 1
        prev = ids[-1] if ids else -1
        n_before = len(ids)
        for k in lp[0][:valid].argmax(axis=-1):
            k = int(k)
            if k != prev and k != blank:
                ids.append(k)
            prev = k
        timeline.append((next_end * 0.01, len(ids) - n_before))
        next_end += shift
    text = "".join(vocab[i] for i in ids if i < len(vocab)).replace("▁", " ").strip()
    return text, timeline


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("wav")
    ap.add_argument("--window_secs", type=float, default=20.0,
                    help="longueur de la fenetre glissante (defaut 20s = la "
                         "duree max d'un clip d'entrainement)")
    a = ap.parse_args()

    cfg = json.loads((DEPLOY / "streaming_config.json").read_text())
    vocab = json.loads((DEPLOY / "vocab.json").read_text(encoding="utf-8"))
    so = ort.SessionOptions(); so.log_severity_level = 3
    sess = ort.InferenceSession(str(DEPLOY / "model_streaming.onnx"), so,
                                providers=["CPUExecutionProvider"])

    samples = read_wav(a.wav)
    print(f"audio : {len(samples)/16000:.1f}s  ({Path(a.wav).name})")
    mels = log_mel_frames(samples)
    print(f"frames log-mel : {len(mels)}\n")

    win_frames = int(a.window_secs * 100)
    for policy, label in (("cumulative", "CUMULATIVE (ce qui tourne aujourd'hui)"),
                          ("sliding", f"GLISSANTE {a.window_secs:.0f}s")):
        text, timeline = run(mels, cfg, sess, vocab, policy, win_frames)
        # Ou la chaine cesse-t-elle d'emettre ? C'est LA mesure : sur device,
        # l'arret d'emission gele l'ancre, donc le curseur.
        last_emit = max((t for t, n in timeline if n > 0), default=0.0)
        total = sum(n for _, n in timeline)
        print(f"── {label}")
        print(f"   tokens emis        : {total}")
        print(f"   dernier token a    : {last_emit:.1f}s  (sur {len(samples)/16000:.1f}s d'audio)")
        if last_emit < len(samples) / 16000 - 3:
            print(f"   ⚠️  PLUS RIEN pendant les {len(samples)/16000 - last_emit:.1f}s finales")
        print(f"   texte : {text[:160]}")
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
