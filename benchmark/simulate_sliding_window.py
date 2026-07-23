"""Simule HORS DEVICE les politiques de segmentation de BufferedTranscriber,
pour regler la fenetre glissante AVANT de l'ecrire en Kotlin.

POURQUOI (2026-07-23) : chaque changement de segmentation tente ce jour-la
directement sur device a casse quelque chose (recouvrement partiel -> ancre qui
saute ; coupe sur frontiere de mot sans couper le texte -> desynchronisation ;
borne a 6s + recouvrement -> segments de 2-3s fragmentaires). Et les trois
"correctifs" testes offline se sont averes PIRES que l'existant (cf.
FONCTIONNALITES_FUTURES.md §4). D'ou ce banc : on regle la politique sur des
chiffres avant de toucher au moteur natif.

Ce que la simulation reproduit fidelement :
  - blocs PCM de 80ms, portier RMS (seuil 0.02, 300ms de silence garde par
    pause au-dela duquel les blocs sont JETES) -- BufferedTranscriber.feed()
  - re-transcription tous les MIN_NEW_SECONDS d'audio neuf
  - gel/coupe avec RETENTION d'audio arrondie a des MOTS ENTIERS, et fusion du
    texte pour ne pas ecrire deux fois les mots retenus (appendMergingOverlap)

Ce qu'elle ne reproduit PAS : l'alignement force et l'ancre (cote Dart). On
mesure donc la qualite du TEXTE produit, qui est l'entree de l'alignement --
si le texte est faux, l'ancre ne peut pas avancer.

POLITIQUES COMPAREES
  actuelle   retention 2s, gel sur pause>=450ms (si segment>=2.5s) ou 12s neufs
  glissante  retention W, glissement des que SLIDE secondes d'audio neuf

Usage :
    PYTHONPATH=benchmark/.venv_nemo/lib/python3.14/site-packages \
      /usr/bin/python3.14 benchmark/simulate_sliding_window.py [--n 12]
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
import onnxruntime as ort
import soundfile as sf

sys.path.insert(0, str(Path(__file__).parent))
from mel_numpy_reference import compute_mel_features  # noqa: E402

BASE = Path(__file__).parent
DEPLOY = BASE / "models/fastconformer-dual-head-v1/deploy/fastconformer-ctc-dual-head"

SR = 16000
BLOCK = 1280                 # 80ms
SILENCE_RMS = 0.02
MAX_SILENCE = int(SR * 0.3)
MIN_NEW = 1.5                # MIN_NEW_SECONDS
COMMIT_SILENCE = 0.45        # DEFAULT_COMMIT_SILENCE_MS
MIN_COMMIT = 2.5             # MIN_COMMIT_SECONDS
MAX_SEGMENT = 12.0           # MAX_SEGMENT_SECONDS
OVERLAP = 2.0                # OVERLAP_SECONDS (politique actuelle)


class Engine:
    def __init__(self):
        self.vocab = json.load(open(DEPLOY / "vocab.json", encoding="utf-8"))
        self.blank = len(self.vocab)
        so = ort.SessionOptions()
        so.log_severity_level = 3
        self.sess = ort.InferenceSession(
            str(DEPLOY / "model.onnx"), so, providers=["CPUExecutionProvider"])
        self.cache = {}

    def decode_words(self, audio):
        """Renvoie [(texte_mot, frame_debut, frame_fin)], + nb de frames.
        Equivalent du greedyDecodeWords a ajouter cote Kotlin."""
        key = (audio.shape[0], float(audio[:64].sum()) if len(audio) >= 64 else 0.0)
        if key in self.cache:
            return self.cache[key]
        if len(audio) < int(SR * 0.25):
            return [], 0
        mel = compute_mel_features(audio, normalize="per_feature")
        lp = self.sess.run(["logprobs"], {
            "audio_signal": mel[None].astype(np.float32),
            "length": np.array([mel.shape[1]], np.int64)})[0][0]
        ids = lp.argmax(-1)
        words, cur, first, last, prev = [], [], -1, -1, -1
        for f, i in enumerate(ids):
            if i != prev and i != self.blank:
                piece = self.vocab[i]
                if piece.startswith("▁") and cur:
                    words.append(("".join(cur).replace("▁", "").strip(), first, last))
                    cur, first = [], -1
                if first < 0:
                    first = f
                last = f
                cur.append(piece)
            prev = i
        if cur:
            words.append(("".join(cur).replace("▁", "").strip(), first, last))
        out = ([w for w in words if w[0]], len(ids))
        self.cache[key] = out
        return out


def rms_blocks(audio):
    for i in range(0, len(audio) - BLOCK + 1, BLOCK):
        b = audio[i:i + BLOCK]
        yield b, np.sqrt(np.mean(b.astype(np.float64) ** 2)) < SILENCE_RMS


def merge_overlap(committed, new_text):
    """appendMergingOverlap : evite de reecrire les mots deja figes."""
    if not committed:
        return new_text
    if not new_text:
        return committed
    c, n = committed.split(), new_text.split()
    for k in range(min(len(c), len(n)), 0, -1):
        if c[-k:] == n[:k]:
            return " ".join(c + n[k:])
    return " ".join(c + n)


def run_policy(engine, audio, sliding, window=6.0, slide=3.0):
    """Rejoue le flux bloc par bloc. sliding=False -> politique actuelle."""
    buf = np.zeros(0, np.float32)
    committed = ""
    retained = 0          # echantillons conserves du glissement precedent
    last_run = 0
    pause = 0
    retained_sil = 0
    n_commits = 0
    max_buf = 0.0

    def do_commit(keep_seconds):
        nonlocal buf, committed, retained, last_run, n_commits
        words, nframes = engine.decode_words(buf)
        if not words or nframes == 0:
            return
        per_frame = len(buf) / nframes
        keep_from = len(buf) - keep_seconds * SR
        # mots ENTIEREMENT dans la zone retenue (debut ET fin)
        whole = [w for w in words if w[1] * per_frame >= keep_from]
        # au moins un mot doit sortir, sinon rien n'avance jamais
        n_keep = min(len(whole), max(0, len(words) - 1))
        if n_keep > 0:
            cut = int(words[len(words) - n_keep][1] * per_frame)
        else:
            cut = len(buf)
        # ⚠️ On ne fige QUE les mots situes AVANT la coupe. Figer tout le texte
        # du buffer (et compter sur merge_overlap pour dedupliquer) marche tant
        # que la retention est courte, mais avec une grande fenetre les memes
        # mots sont re-figes a chaque glissement : la moindre variation de leur
        # transcription echappe a la fusion et les DUPLIQUE. Mesure 2026-07-23
        # avec cette version naive : WER 98-135% (contre 29,8% a la politique
        # actuelle) -- c'est exactement le piege annonce par le commentaire de
        # BufferedTranscriber.kt:625 ("figer QUE le texte des mots situes avant
        # la coupe"). La correspondance texte/audio par mot existe justement
        # pour ca : elle rend cette decoupe possible.
        leaving = words[:len(words) - n_keep] if n_keep > 0 else words
        text = " ".join(w[0] for w in leaving)
        committed = merge_overlap(committed, text)
        buf = buf[cut:]
        retained = len(buf)
        last_run = len(buf)
        n_commits += 1

    for blk, is_sil in rms_blocks(audio):
        if is_sil:
            pause += len(blk)
            if retained_sil >= MAX_SILENCE:
                pass                      # bloc JETE (coutures)
            else:
                retained_sil += len(blk)
                buf = np.concatenate([buf, blk])
        else:
            retained_sil = 0
            pause = 0
            buf = np.concatenate([buf, blk])

        new_s = (len(buf) - retained) / SR
        max_buf = max(max_buf, len(buf) / SR)

        if sliding:
            if new_s >= slide:
                do_commit(window)
                continue
        else:
            if (is_sil and pause >= COMMIT_SILENCE * SR and new_s >= MIN_COMMIT) \
               or new_s >= MAX_SEGMENT:
                do_commit(OVERLAP)
                continue

        if (len(buf) - last_run) >= MIN_NEW * SR:
            last_run = len(buf)           # apercu (n'affecte pas le texte fige)

    words, _ = engine.decode_words(buf)
    if words:
        committed = merge_overlap(committed, " ".join(w[0] for w in words))
    return committed, n_commits, max_buf


def wer(ref, hyp):
    r, h = ref.split(), hyp.split()
    d = np.zeros((len(r) + 1, len(h) + 1), np.int32)
    d[:, 0] = np.arange(len(r) + 1); d[0, :] = np.arange(len(h) + 1)
    for i in range(1, len(r) + 1):
        for j in range(1, len(h) + 1):
            d[i, j] = min(d[i - 1, j] + 1, d[i, j - 1] + 1,
                          d[i - 1, j - 1] + (r[i - 1] != h[j - 1]))
    return int(d[len(r), len(h)]), len(r)


def remap(p):
    return (p.replace("/mnt/ssd5/Coran Karim/", str(BASE.parent) + "/")
             .replace("/mnt/hdd/Coran Karim/", "/run/media/kafai/HDD/Coran Karim/"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=12)
    args = ap.parse_args()

    eng = Engine()
    val = [json.loads(l) for l in open(
        BASE / "nemo_manifests_mixed/val_canonical.jsonl", encoding="utf-8")]
    rng = np.random.default_rng(11)
    rng.shuffle(val)
    clips = [r for r in val if 6.0 <= r["duration"] <= 9.0][:args.n]

    configs = [("ACTUELLE (2s/12s)", None, None),
               ("glissante W=8 S=4", 8.0, 4.0),
               ("glissante W=6 S=3", 6.0, 3.0),
               ("glissante W=5 S=2", 5.0, 2.0),
               ("glissante W=4 S=2", 4.0, 2.0)]

    for label, hesitant in (("RECITATION FLUIDE", False),
                            ("RECITATION HESITANTE (4 pauses de 2s)", True)):
        print(f"\n{'=' * 70}\n{label}\n{'=' * 70}")
        tot = {c[0]: [0, 0] for c in configs}
        bufmax = {c[0]: 0.0 for c in configs}
        for r in clips:
            a, _ = sf.read(remap(r["audio_filepath"]), dtype="float32")
            if hesitant:
                step = len(a) // 5
                parts = []
                for i in range(5):
                    parts.append(a[i * step:(i + 1) * step])
                    if i < 4:
                        parts.append(np.zeros(int(2.0 * SR), np.float32))
                a = np.concatenate(parts)
            for name, w, s in configs:
                txt, nc, mb = run_policy(eng, a, sliding=w is not None,
                                         window=w or 0, slide=s or 0)
                e, n = wer(r["text"], txt)
                tot[name][0] += e; tot[name][1] += n
                bufmax[name] = max(bufmax[name], mb)
        print(f"  {'politique':<22}{'WER':>8}{'buffer max':>13}")
        print(f"  {'-' * 22}{'-' * 8}{'-' * 13}")
        for name, _, _ in configs:
            print(f"  {name:<22}{100 * tot[name][0] / tot[name][1]:>7.1f}%"
                  f"{bufmax[name]:>11.1f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
