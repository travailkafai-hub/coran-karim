"""Compare TROIS politiques de decoupage sur du vrai audio, en mesurant ce qui
cause reellement les faux verdicts : les mots qui tombent EN FRONTIERE.

IDEE MESUREE (utilisateur, 2026-07-27) : avec UNE seule decoupe, un mot en
frontiere l'est DEUX FOIS -- le segment qui finit dessus le tronque a droite, le
segment suivant qui commence dessus le tronque a gauche. C'est pourquoi le
mecanisme de seconde chance deja present (`deferredOnceIndex` dans
BufferedTranscriber.kt) ne le sauve pas : il lui redonne sa chance a un AUTRE
bord, jamais au milieu. Deux decoupes DECALEES cassent ca par construction : un
mot en frontiere dans A est au milieu dans B.

Ce n'est PAS ajouter de la tolerance (cf. regle projet "pas de correctif
palliatif") : on remplace une mesure corrompue par une mesure valide. La
distinction est essentielle -- et c'est pourquoi la selection ne doit porter QUE
sur les mots d'extremite. Prendre "le meilleur des deux" sur TOUS les mots
reviendrait a choisir systematiquement le verdict le plus indulgent, donc a
gonfler la tolerance en silence : sur les mots interieurs les deux decoupes
voient la meme chose, elles sont d'accord, la comparaison n'apporte rien et
n'ouvre qu'un risque.

POLITIQUES COMPAREES
  actuelle    : decoupe unique, gel sur pause >=450ms (si segment >=2,5s) ou
                borne dure 12s -- l'etat en service.
  double      : DEUX decoupes independantes, decalees d'un demi-segment. Cout
                ~2x l'inference.
  chevauchant : UNE passe, mais chaque segment empiete de OVERLAP sur le
                precedent, de sorte que chaque frontiere devient INTERIEURE au
                segment suivant. Cout ~1,3x seulement.
                ⚠️ Piege documente : une fenetre glissante naive avait donne un
                WER > 100 % par DUPLICATION de texte. La parade implementee ici
                est de dissocier deux choses que le code de production confond :
                le texte FIGE (uniquement la partie non chevauchee, donc jamais
                ecrite deux fois) et le contexte qui sert a JUGER (le segment
                entier, chevauchement compris).

METRIQUE PRINCIPALE : ce n'est pas seulement le WER, c'est le nombre de mots
attendus qui tombent a moins de FRONTIER_MS d'un bord de segment -- ce sont eux
qui produisent les `entendu=""`, les fragments et les faux rouges mesures les
jours precedents.

USAGE
    PYTHONPATH=benchmark/.venv_nemo/lib/python3.14/site-packages \
      CAUSAL_DEPLOY=<dossier> /usr/bin/python3.14 benchmark/bench_double_decoupage.py <wav...>
"""
import os
import sys
import wave
from pathlib import Path

import numpy as np
import onnxruntime as ort

sys.path.insert(0, str(Path(__file__).parent))
from mel_numpy_reference import compute_mel_features  # noqa: E402

BASE = Path(__file__).parent
DEPLOY = Path(os.environ.get(
    "CAUSAL_DEPLOY",
    "/run/media/kafai/HDD/Coran Karim/benchmark/models/"
    "fastconformer-streaming-causal-v1-lr3e4/deploy/fastconformer-ctc-causal-v1"))

SR = 16000
BLOCK = 1280                  # 80 ms, la taille livree par le micro
SILENCE_RMS = 0.02
MAX_SILENCE = int(SR * 0.3)   # MAX_SILENCE_SAMPLES cote Kotlin
COMMIT_SILENCE = 0.45         # DEFAULT_COMMIT_SILENCE_MS
MIN_COMMIT = 2.5              # MIN_COMMIT_SECONDS
MAX_SEGMENT = 12.0            # MAX_SEGMENT_SECONDS
FRONTIER_MS = 300             # marge sous laquelle un mot est dit "en frontiere"


def read_wav(p):
    with wave.open(str(p), "rb") as w:
        assert w.getframerate() == SR and w.getnchannels() == 1, p
        raw = w.readframes(w.getnframes())
    return np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0


class Engine:
    def __init__(self, deploy=DEPLOY):
        import json
        self.vocab = json.load(open(deploy / "vocab.json", encoding="utf-8"))
        self.blank = len(self.vocab)
        so = ort.SessionOptions()
        so.log_severity_level = 3
        self.sess = ort.InferenceSession(
            str(deploy / "model.onnx"), so, providers=["CPUExecutionProvider"])
        self.calls = 0

    def decode_words(self, audio):
        """[(mot, frame_debut, frame_fin)] + nb de frames — meme decoupage en
        mots que greedyDecodeWords cote Kotlin (un mot commence a un token
        prefixe par le marqueur de debut de mot)."""
        if len(audio) < int(SR * 0.25):
            return [], 0
        self.calls += 1
        mel = compute_mel_features(audio, normalize="per_feature")
        lp = self.sess.run(["logprobs"], {
            "audio_signal": mel[None].astype(np.float32),
            "length": np.array([mel.shape[1]], np.int64)})[0][0]
        ids = lp.argmax(-1)
        words, cur, first, last, prev = [], [], -1, -1, -1
        for f, i in enumerate(ids):
            i = int(i)
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
        return [w for w in words if w[0]], len(ids)


def gated_stream(audio):
    """Reproduit le portier RMS de BufferedTranscriber.feed() : au-dela de
    MAX_SILENCE conserve par pause, les blocs silencieux sont JETES.

    Renvoie l'audio REELLEMENT vu par le modele (blocs conserves concatenes) et,
    pour chaque bloc conserve, s'il etait silencieux et la duree de la pause en
    cours. BUG CORRIGE (2026-07-27) : la premiere version comptait les positions
    de coupe sur le flux CONSERVE puis les appliquait sur l'audio D'ORIGINE --
    deux echelles de temps differentes des qu'un bloc est jete, ce qui donnait
    1 seul segment sur 187 s d'audio. Tout se passe desormais dans l'echelle du
    flux conserve, celle que le modele voit.
    """
    kept, meta, retained, pause = [], [], 0, 0
    for i in range(0, len(audio) - BLOCK + 1, BLOCK):
        b = audio[i:i + BLOCK]
        silent = np.sqrt(np.mean(b.astype(np.float64) ** 2)) < SILENCE_RMS
        if not silent:
            retained, pause = 0, 0
            kept.append(b); meta.append((False, 0))
        else:
            pause += BLOCK
            if retained < MAX_SILENCE:
                retained += BLOCK
                kept.append(b); meta.append((True, pause))
    return (np.concatenate(kept) if kept else np.zeros(0, np.float32)), meta


def segments_of(meta, offset_s=0.0):
    """Bornes (debut, fin) des segments DANS LE FLUX CONSERVE, selon la
    politique de production : gel sur pause franche si le segment est assez
    long, sinon borne dure. [offset_s] raccourcit la PREMIERE coupe -- c'est ce
    qui rend les deux decoupes independantes."""
    segs, start, seg = [], 0, 0
    limit = max(MIN_COMMIT, MAX_SEGMENT - offset_s) if offset_s else MAX_SEGMENT
    for k, (silent, pause) in enumerate(meta):
        seg += BLOCK
        s = seg / SR
        if (s >= MIN_COMMIT and silent and pause >= COMMIT_SILENCE * SR) or s >= limit:
            end = (k + 1) * BLOCK
            segs.append((start, end))
            start, seg, limit = end, 0, MAX_SEGMENT
    total = len(meta) * BLOCK
    if start < total:
        segs.append((start, total))
    return segs


def frontier_words(eng, segs, audio, overlap=0):
    """Compte les mots decodes qui touchent un bord de segment (a moins de
    FRONTIER_MS) -- la population qui produit les faux verdicts."""
    n_front = n_tot = 0
    texts = []
    for a, b in segs:
        lo = max(0, a - overlap)
        words, nf = eng.decode_words(audio[lo:b])
        if not words:
            continue
        # 1 frame ~ 80 ms (subsampling 8 x hop 10 ms)
        margin = FRONTIER_MS / 80.0
        for w, f0, f1 in words:
            n_tot += 1
            if f0 <= margin or f1 >= nf - margin:
                n_front += 1
        texts.append(" ".join(w for w, _, _ in words))
    return n_front, n_tot, texts


def main():
    wavs = [Path(p) for p in sys.argv[1:]]
    if not wavs:
        print("usage: bench_double_decoupage.py <fichier.wav ...>")
        return 1
    eng = Engine()
    print(f"modele : {DEPLOY.name}\n")
    tot = {k: [0, 0, 0] for k in ("actuelle", "double", "chevauchant")}

    for p in wavs:
        raw = read_wav(p)
        audio, meta = gated_stream(raw)
        print(f"── {p.name}  ({len(raw)/SR:.1f}s brut -> {len(audio)/SR:.1f}s apres portier RMS)")

        # 1. politique en service
        c0 = eng.calls
        segsA = segments_of(meta)
        fA, tA, _ = frontier_words(eng, segsA, audio)
        callsA = eng.calls - c0
        print(f"   actuelle     : {len(segsA):2d} segments, "
              f"{fA:3d}/{tA:3d} mots en frontiere ({fA/max(tA,1):.0%}), "
              f"{callsA} inferences")

        # 2. deux decoupes independantes, decalees d'un demi-segment
        c0 = eng.calls
        segsB = segments_of(meta, offset_s=MAX_SEGMENT / 2)
        fB, tB, _ = frontier_words(eng, segsB, audio)
        # un mot n'est problematique que s'il est en frontiere dans LES DEUX
        inter = min(fA, fB)
        callsB = eng.calls - c0 + callsA
        print(f"   double       : {len(segsB):2d} segments (decalee), "
              f"{fB:3d}/{tB:3d} en frontiere -> "
              f"{inter:3d} restants si on croise ({inter/max(tA,1):.0%}), "
              f"{callsB} inferences")

        # 3. chevauchement : jugement sur segment etendu a gauche
        c0 = eng.calls
        ov = int(SR * 3.0)
        fC, tC, _ = frontier_words(eng, segsA, audio, overlap=ov)
        callsC = eng.calls - c0
        print(f"   chevauchant  : {len(segsA):2d} segments +3s de contexte, "
              f"{fC:3d}/{tC:3d} en frontiere ({fC/max(tC,1):.0%}), "
              f"{callsC} inferences")

        for k, (f, t) in zip(("actuelle", "double", "chevauchant"),
                             ((fA, tA), (inter, tA), (fC, tC))):
            tot[k][0] += f
            tot[k][1] += t
        tot["actuelle"][2] += callsA
        tot["double"][2] += callsB
        tot["chevauchant"][2] += callsC
        print()

    print("=" * 68)
    print(f"{'politique':<14} {'mots en frontiere':<20} {'part':>6} {'inferences':>11}")
    print("-" * 68)
    for k, (f, t, c) in tot.items():
        print(f"{k:<14} {f:>7} / {t:<10} {f/max(t,1):>5.0%} {c:>11}")
    print("\nLecture : la part de mots en frontiere est la cause mesuree des")
    print("`entendu=\"\"`, des fragments et des faux rouges. La faire baisser est")
    print("l'objectif ; le cout en inferences est ce qu'on paie pour l'obtenir.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
