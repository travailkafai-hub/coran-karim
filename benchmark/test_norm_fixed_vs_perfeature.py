"""Normalisation per_feature vs stats FIXES : la derive est-elle la cause, et
le checkpoint tolere-t-il le changement ?

CONTEXTE (mesure device 2026-07-23, log asm.log, sourate 90) : le verset 90:11
(فَلَا ٱقْتَحَمَ ٱلْعَقَبَةَ) n'a jamais ete valide alors qu'il avait ete
CORRECTEMENT transcrit une fois. Chaine observee :
  1. hesitation -> 5,4s sur 6,4s d'audio entrant jetees par le portier RMS
     (BufferedTranscriber:549, 300ms de silence garde par pause) ;
  2. la transcription s'effondre QUAND LE BUFFER GROSSIT :
        18:35:25  buffer 1s  ->  "فَلَا ٱقْتَحَمَ ٱلْعَقَبَ"   (3 mots, juste)
        18:35:29  buffer 3s  ->  "فَلَاقْ"                      (1 mot)
        18:35:30  buffer 4s  ->  ""                             (0 mot)
  3. l'alignement n'a plus rien a apparier -> mots=0 sept fois, ancre figee a
     42 pendant 22s.
Correlation 3/3 sur la session : les SEULS segments ou l'apercu regresse sont
les 3 intervalles de perte audio massive.

HYPOTHESE A TESTER : la cause est la normalisation "per_feature"
(MelSpectrogram.kt:234, mean/std recalcules sur TOUT le buffer a chaque appel).
Des stats FIXES supprimeraient la derive quelle que soit la taille du buffer.
C'est la piste notee en fin de header de BufferedTranscriber.kt, jamais testee
"faute de temps de validation".

⚠️ CE QUE CE SCRIPT NE PROUVE PAS : le modele a ete ENTRAINE en per_feature.
Des stats fixes changent la distribution d'entree -- d'ou l'etape 3, qui est
la condition d'acceptation, pas un bonus.

  Etape 1  effet du SILENCE accumule (parole fixe + silence croissant)
  Etape 2  effet de la LONGUEUR seule (parole reelle croissante, sans silence)
  Etape 3  non-regression WER sur val_canonical

Usage :
    PYTHONPATH=benchmark/.venv_nemo/lib/python3.14/site-packages \
      /usr/bin/python3.14 benchmark/test_norm_fixed_vs_perfeature.py [--n-wer 200]
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path

import numpy as np
import onnxruntime as ort
import soundfile as sf

sys.path.insert(0, str(Path(__file__).parent))
from mel_numpy_reference import compute_mel_features  # noqa: E402

BASE = Path(__file__).parent
DEPLOY = BASE / "models/fastconformer-dual-head-v1/deploy/fastconformer-ctc-dual-head"
VAL = BASE / "nemo_manifests_mixed/val_canonical.jsonl"
STATS_CACHE = BASE / "logs/mel_fixed_stats.json"

SR = 16000
BLOCK = 1280                     # 80ms, comme les blocs PCM du device
SILENCE_RMS = 0.02               # BufferedTranscriber.SILENCE_RMS_THRESHOLD
MAX_SILENCE = int(SR * 0.3)      # BufferedTranscriber.MAX_SILENCE_SAMPLES


def remap(p: str) -> str:
    """Manifests ecrits sur une autre machine (cf. CLAUDE.md)."""
    return (p.replace("/mnt/ssd5/Coran Karim/", str(BASE.parent) + "/")
             .replace("/mnt/hdd/Coran Karim/", "/run/media/kafai/HDD/Coran Karim/"))


# ----------------------------------------------------------------- decodage
class Decoder:
    def __init__(self):
        self.vocab = json.load(open(DEPLOY / "vocab.json", encoding="utf-8"))
        self.blank = len(self.vocab)
        so = ort.SessionOptions()
        so.log_severity_level = 3
        self.sess = ort.InferenceSession(
            str(DEPLOY / "model.onnx"), so, providers=["CPUExecutionProvider"])

    def transcribe(self, audio: np.ndarray, norm) -> str:
        mel = compute_mel_features(audio, normalize=norm)          # (80, T)
        feats = mel[None].astype(np.float32)
        length = np.array([mel.shape[1]], dtype=np.int64)
        lp = self.sess.run(["logprobs"],
                           {"audio_signal": feats, "length": length})[0][0]
        ids = lp.argmax(-1)
        out, prev = [], -1
        for i in ids:
            if i != prev and i != self.blank:
                out.append(self.vocab[i])
            prev = i
        return "".join(out).replace("▁", " ").strip()


# ------------------------------------------------------- portier RMS device
def rms_gate(audio: np.ndarray):
    """Reproduit BufferedTranscriber.feed() : bloc de 80ms sous le seuil =
    silence ; au-dela de 300ms conserves pour UNE pause, les blocs suivants
    sont JETES. Retourne (audio_conserve, secondes_jetees)."""
    kept, retained, dropped = [], 0, 0
    for i in range(0, len(audio) - BLOCK + 1, BLOCK):
        blk = audio[i:i + BLOCK]
        if np.sqrt(np.mean(blk.astype(np.float64) ** 2)) >= SILENCE_RMS:
            retained = 0
            kept.append(blk)
        elif retained >= MAX_SILENCE:
            dropped += len(blk)
        else:
            retained += len(blk)
            kept.append(blk)
    return (np.concatenate(kept) if kept else np.zeros(0, np.float32),
            dropped / SR)


# ------------------------------------------------------------- stats fixes
def fixed_stats(n_clips: int = 300):
    if STATS_CACHE.exists():
        d = json.load(open(STATS_CACHE))
        if d.get("n_clips") == n_clips:
            return np.array(d["mean"]), np.array(d["std"])
    print(f"  calcul des stats fixes sur {n_clips} clips d'entrainement...")
    rows = []
    with open(BASE / "nemo_manifests_mixed/train_mixed.jsonl", encoding="utf-8") as f:
        for line in f:
            rows.append(json.loads(line))
            if len(rows) >= n_clips * 4:
                break
    rng = np.random.default_rng(7)
    rng.shuffle(rows)
    s = np.zeros(80); s2 = np.zeros(80); n = 0
    used = 0
    for r in rows:
        p = remap(r["audio_filepath"])
        if not os.path.exists(p):
            continue
        a, _ = sf.read(p, dtype="float32")
        lm = compute_mel_features(a, normalize=None).astype(np.float64)
        s += lm.sum(1); s2 += (lm ** 2).sum(1); n += lm.shape[1]
        used += 1
        if used >= n_clips:
            break
    mean = s / n
    std = np.sqrt(np.maximum(s2 / n - mean ** 2, 1e-12))
    STATS_CACHE.parent.mkdir(parents=True, exist_ok=True)
    json.dump({"n_clips": n_clips, "n_frames": int(n),
               "mean": mean.tolist(), "std": std.tolist()}, open(STATS_CACHE, "w"))
    print(f"  -> {used} clips, {n} frames")
    return mean, std


# ------------------------------------------------------------------ metrics
def wer(ref: str, hyp: str):
    r, h = ref.split(), hyp.split()
    d = np.zeros((len(r) + 1, len(h) + 1), dtype=np.int32)
    d[:, 0] = np.arange(len(r) + 1)
    d[0, :] = np.arange(len(h) + 1)
    for i in range(1, len(r) + 1):
        for j in range(1, len(h) + 1):
            d[i, j] = min(d[i - 1, j] + 1, d[i, j - 1] + 1,
                          d[i - 1, j - 1] + (r[i - 1] != h[j - 1]))
    return d[len(r), len(h)], len(r)


def head(t):
    print(f"\n{'=' * 74}\n{t}\n{'=' * 74}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n-wer", type=int, default=200)
    args = ap.parse_args()

    dec = Decoder()
    mean, std = fixed_stats()
    FIX = (mean, std)

    val = [json.loads(l) for l in open(VAL, encoding="utf-8")]
    rng = np.random.default_rng(11)
    rng.shuffle(val)

    # clip de reference : assez long pour etre coupe en prefixes
    ref = next(r for r in val if 6.0 <= r["duration"] <= 9.0)
    audio, _ = sf.read(remap(ref["audio_filepath"]), dtype="float32")

    # ---------------------------------------------------------------- etape 1
    head("ETAPE 1 — effet du SILENCE ACCUMULE (la parole ne change PAS)")
    print("  Meme parole a chaque ligne ; on ajoute du silence APRES, exactement")
    print("  comme le portier RMS en conserve 300ms par pause. Si la transcription")
    print("  change, c'est la normalisation, pas l'acoustique.\n")
    speech = audio[:int(3.0 * SR)]
    base_pf = dec.transcribe(speech, "per_feature")
    base_fx = dec.transcribe(speech, FIX)
    print(f"  {'silence ajoute':<16}{'per_feature':<34}{'stats fixes'}")
    print(f"  {'-' * 16}{'-' * 34}{'-' * 30}")
    chg_pf = chg_fx = 0
    for sil in (0.0, 0.5, 1.0, 2.0, 4.0, 8.0, 15.0):
        buf = np.concatenate([speech, np.zeros(int(sil * SR), np.float32)])
        t_pf = dec.transcribe(buf, "per_feature")
        t_fx = dec.transcribe(buf, FIX)
        d_pf = "" if t_pf == base_pf else " <<<"
        d_fx = "" if t_fx == base_fx else " <<<"
        chg_pf += bool(d_pf); chg_fx += bool(d_fx)
        print(f"  {sil:>6.1f}s        {t_pf[:30]:<30}{d_pf:<4}{t_fx[:26]:<26}{d_fx}")
    print(f"\n  => transcription ALTEREE : per_feature {chg_pf}/7, "
          f"stats fixes {chg_fx}/7")

    # ---------------------------------------------------------------- etape 2
    head("ETAPE 2 — effet de la LONGUEUR seule (parole reelle croissante)")
    print("  Prefixes croissants de vraie recitation, sans silence ajoute.")
    print("  Un prefixe deja transcrit ne doit pas se degrader quand on rallonge.\n")
    print(f"  {'prefixe':<10}{'per_feature':<36}{'stats fixes'}")
    print(f"  {'-' * 10}{'-' * 36}{'-' * 30}")
    for frac in (0.25, 0.4, 0.55, 0.7, 0.85, 1.0):
        buf = audio[:int(len(audio) * frac)]
        t_pf = dec.transcribe(buf, "per_feature")
        t_fx = dec.transcribe(buf, FIX)
        print(f"  {len(buf)/SR:>5.1f}s    {t_pf[:32]:<36}{t_fx[:28]}")
    print(f"\n  attendu : {ref['text'][:60]}")

    # ------------------------------------------------- etape 2bis : le portier
    head("ETAPE 2bis — le portier RMS sur un clip reel (combien jette-t-il ?)")
    kept, drop = rms_gate(audio)
    print(f"  clip {len(audio)/SR:.1f}s -> conserve {len(kept)/SR:.1f}s, "
          f"jete {drop:.1f}s ({100*drop/(len(audio)/SR):.0f}%)")
    print(f"  per_feature sur l'audio filtre : {dec.transcribe(kept, 'per_feature')[:60]}")
    print(f"  stats fixes  sur l'audio filtre : {dec.transcribe(kept, FIX)[:60]}")

    # ---------------------------------------------------------------- etape 3
    head(f"ETAPE 3 — NON-REGRESSION WER sur {args.n_wer} clips val_canonical")
    print("  Condition d'acceptation : le checkpoint n'a JAMAIS vu de stats fixes")
    print("  a l'entrainement. Si le WER se degrade, la piste est morte.\n")
    e_pf = n_pf = e_fx = 0
    t0 = time.time()
    done = 0
    for r in val:
        p = remap(r["audio_filepath"])
        if not os.path.exists(p):
            continue
        a, _ = sf.read(p, dtype="float32")
        ep, nr = wer(r["text"], dec.transcribe(a, "per_feature"))
        ef, _ = wer(r["text"], dec.transcribe(a, FIX))
        e_pf += ep; e_fx += ef; n_pf += nr
        done += 1
        if done % 25 == 0:
            print(f"    {done}/{args.n_wer}  per_feature {100*e_pf/n_pf:.2f}%  "
                  f"fixes {100*e_fx/n_pf:.2f}%   ({time.time()-t0:.0f}s)")
        if done >= args.n_wer:
            break
    print(f"\n  {'per_feature (actuel)':<26} WER {100*e_pf/n_pf:.2f}%")
    print(f"  {'stats fixes':<26} WER {100*e_fx/n_pf:.2f}%")
    delta = 100 * (e_fx - e_pf) / n_pf
    print(f"  {'ecart':<26} {delta:+.2f} point(s)")
    print("\n  VERDICT : " + (
        "stats fixes VIABLES (ecart <= 0.5 pt)" if delta <= 0.5 else
        "stats fixes REJETEES -- le checkpoint ne les tolere pas ; "
        "il faut passer par le buffer glissant en gardant per_feature"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
