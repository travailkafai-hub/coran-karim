"""Mesure les DUREES REELLES par mot, hors ligne, depuis les clips WAV captes
sur le telephone -- en contournant la segmentation temps reel.

IDEE (utilisateur, 2026-07-27) : « avec mes wav est-ce qu'il est permis de
deduire les timings malgre les retards de validation ? » Oui, et c'est la bonne
facon de le faire. Le retard de validation est un probleme de LIVRAISON en temps
reel ; il ne touche pas le contenu audio. Les clips contiennent la voix intacte.

CE QUI REND LA MESURE VALIDE -- et qu'aucune mesure sur device ne peut donner :
les clips sont CONTIGUS ET SANS RECOUVREMENT dans le flux consomme (cote Kotlin,
`consomme` = ce qui part dans le clip, `conserve` = ce qui reste dans le buffer
pour le segment suivant). Les concatener dans l'ordre de gel reconstitue donc un
flux continu ou LES MOTS COUPES AUX FRONTIERES DE SEGMENT SONT RECOLLES. Or ce
sont eux qui polluent toute mesure faite en direct : sur la session du 15:17,
12 des 18 erreurs (67 %) tombaient sur un bord de segment, dont deux avec
gop=0,00 et free~0 -- le modele etait CERTAIN de ce qu'il entendait, il n'avait
recu qu'un fragment.

CE QUE LA MESURE NE PEUT PAS DONNER, et qu'il ne faut donc pas lui demander :
le portier RMS a deja jete les silences (plafonnes a 300 ms par pause) avant
l'ecriture des clips. Les DUREES D'ARTICULATION sont donc mesurables, les
PAUSES ne le sont pas. C'est suffisant : un plancher porte sur l'articulation.

POURQUOI PAR FENETRES ET PAS D'UN SEUL BLOC : le modele est entraine sur des
clips courts et le projet a mesure (2026-07-05) que la normalisation
per_feature derive nettement des ~10 s de buffer. Aligner 190 s d'un coup
reproduirait donc en pire le defaut qu'on cherche a eviter. On decoupe en
fenetres de WINDOW_S avec un recouvrement de OVERLAP_S, et on ne retient les
frames d'un mot QUE depuis la fenetre ou il est le plus INTERIEUR -- meme
principe que la politique "chevauchant" de bench_double_decoupage.py.

⚠️ ETAT AU 2026-07-27 : LE BANC N'EST PAS ENCORE EXPLOITABLE.

CE QUI EST DEMONTRE (et c'etait la question posee) : l'audio des clips EST
utilisable, la concatenation est correcte et l'ordre des mots est preserve. Le
decodage libre sur le flux concatene se lit sans ambiguite --
  [ 10-18s] ذَٰلِكَ ٱلْكِتَـٰبُ لَا رَيْبَ فِيهِ
  [ 40-48s] إِنَّ ٱلَّذِينَ كَفَرُوا۟ سَوَآءٌ
  [150-158s] وَتَرَكَهُمْ فِى ظُلُمَـٰ لَّا يُبْصِرُونَ
-- donc le retard de validation ne corrompt PAS le contenu, et deduire les
durees hors ligne est bien possible.

CE QUI NE MARCHE PAS : le placement de l'ancre par fenetre. 8 mots mesures sur
239. Deux causes identifiees, non corrigees :
 1. L'ancre est estimee depuis les mots que la DP a places dans la fenetre
    precedente -- or ces placements peuvent etre FANTOMES (la fenetre 0-8 s ne
    contient qu'un mot au decodage libre, mais la DP y a "place" 8 mots avec 1-2
    frames chacun). Une estimation batie sur du bruit derive immediatement.
 2. Des que l'ancre et la position audio divergent, le chemin tout-blank devient
    le moins couteux (les mots de la cible ne sont pas dans la fenetre), la DP
    ne place plus rien, et l'ancre cesse d'avancer -- verrouillage definitif.
    C'est le meme decrochage que cote app, ici amplifie par (1).

CE QU'IL FAUT FAIRE (conception, pas rustine) : ancrer chaque fenetre sur le
DECODAGE LIBRE et non sur les placements de la DP. Le libre est fiable (cf. les
extraits ci-dessus), il suffit de l'apparier a la suite attendue pour connaitre
la plage de mots reellement presente, PUIS lancer la DP sur cette plage. Tant
que ce n'est pas fait, ne pas se servir des chiffres sortis par ce script.

USAGE
    PYTHONPATH=benchmark/.venv_nemo/lib/python3.14/site-packages \
      /usr/bin/python3.14 benchmark/bench_durees_depuis_clips.py \
        --clips <dossier_session> --log <recitation_diagnostic.log> \
        --session-start <horodatage BUILD>
"""
import argparse
import json
import os
import re
import sys
import wave
from pathlib import Path

import numpy as np
import onnxruntime as ort

sys.path.insert(0, str(Path(__file__).parent))
from mel_numpy_reference import compute_mel_features  # noqa: E402

DEPLOY = Path(os.environ.get(
    "CAUSAL_DEPLOY",
    "/run/media/kafai/HDD/Coran Karim/benchmark/models/"
    "fastconformer-streaming-causal-v1-lr3e4/deploy/fastconformer-ctc-causal-v1"))

SR = 16000
MS_PER_FRAME = 80        # subsampling 8 x stride 10 ms
# MESURE (2026-07-27) : a 20 s de fenetre, la DP ne placait que 8 mots sur 239
# -- c'est la derive de normalisation per_feature deja documentee (nette des
# ~10 s de buffer, cf. BufferedTranscriber v3 du 2026-07-05) qui frappe, celle
# que ce banc pretendait justement eviter. On reste donc dans le regime ou le
# modele fonctionne, avec un recouvrement large pour recoller les bords.
WINDOW_S = float(os.environ.get("WINDOW_S", 8.0))
OVERLAP_S = float(os.environ.get("OVERLAP_S", 3.0))


def read_wav(p):
    with wave.open(str(p), "rb") as w:
        assert w.getframerate() == SR and w.getnchannels() == 1, p
        raw = w.readframes(w.getnframes())
    return np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0


def load_clips(d):
    """Clips tries par horodatage de GEL (leur nom), donc dans l'ordre du flux
    audio consomme -- c'est ce qui garantit la contiguite."""
    clips = sorted(Path(d).glob("clip_*.wav"), key=lambda p: int(p.stem[5:]))
    audio, bounds, t = [], [], 0
    for c in clips:
        a = read_wav(c)
        audio.append(a)
        bounds.append((c.name, t, t + len(a)))
        t += len(a)
    return np.concatenate(audio), bounds


def expected_words(log_path, session_start):
    """Suite (index -> mot attendu) lue dans le log de la session : les lignes
    [GOP] portent l'index ABSOLU et le texte attendu. On prend le log comme
    source plutot que de reconstruire le texte, pour ne pas reimplementer la
    normalisation Dart et risquer un desaccord silencieux."""
    out = {}
    started = False
    for line in open(log_path, encoding="utf-8", errors="replace"):
        if session_start in line:
            started = True
        if not started:
            continue
        m = re.search(r'\[GOP\] mot=(\d+) "([^"]*)"', line)
        if m:
            out.setdefault(int(m.group(1)), m.group(2))
    return out


class Aligner:
    """Alignement force CTC (Viterbi sur les etats etendus), transcription
    fidele de ForcedAligner.kt : etats [blank, tok0, blank, tok1, ...], et les
    trois transitions rester / avancer / sauter-le-blank-entre-deux-tokens-
    differents."""

    def __init__(self):
        self.vocab = json.load(open(DEPLOY / "vocab.json", encoding="utf-8"))
        self.blank = len(self.vocab)
        self.wtok = json.load(open(DEPLOY / "word_tokens.json", encoding="utf-8"))
        so = ort.SessionOptions()
        so.log_severity_level = 3
        self.sess = ort.InferenceSession(
            str(DEPLOY / "model.onnx"), so, providers=["CPUExecutionProvider"])

    def logprobs(self, audio):
        mel = compute_mel_features(audio, normalize="per_feature")
        return self.sess.run(["logprobs"], {
            "audio_signal": mel[None].astype(np.float32),
            "length": np.array([mel.shape[1]], np.int64)})[0][0]

    def align(self, lp, word_tokens):
        """Retourne, par mot, (premiere_frame, derniere_frame, frames_non_blank)
        ou None si le mot n'a recu aucune frame."""
        flat, owner = [], []
        for w, toks in enumerate(word_tokens):
            for tk in toks:
                flat.append(tk)
                owner.append(w)
        n = len(flat)
        if n == 0 or lp.shape[0] == 0:
            return None
        T, S = lp.shape[0], 2 * n + 1
        NEG = -1e30

        def emit(t, s):
            return lp[t][self.blank] if s % 2 == 0 else lp[t][flat[(s - 1) // 2]]

        prev = np.full(S, NEG, dtype=np.float64)
        prev[0] = emit(0, 0)
        if S > 1:
            prev[1] = emit(0, 1)
        bp = np.zeros((T, S), dtype=np.int8)
        for t in range(1, T):
            cur = np.full(S, NEG, dtype=np.float64)
            for s in range(S):
                best, frm = prev[s], 0
                if s >= 1 and prev[s - 1] > best:
                    best, frm = prev[s - 1], 1
                if (s >= 3 and s % 2 == 1
                        and flat[(s - 1) // 2] != flat[(s - 3) // 2]
                        and prev[s - 2] > best):
                    best, frm = prev[s - 2], 2
                if best > NEG:
                    cur[s] = best + emit(t, s)
                bp[t][s] = frm
            prev = cur
        # Fin PARTIELLE : meilleur etat final sur TOUS les etats (l'audio peut
        # s'arreter au milieu du texte attendu) -- meme regle que le Kotlin.
        end = int(np.argmax(prev))
        if prev[end] <= NEG:
            return None
        path = np.zeros(T, dtype=np.int32)
        s = end
        for t in range(T - 1, -1, -1):
            path[t] = s
            if t > 0:
                s -= bp[t][s]
        res = [None] * len(word_tokens)
        for t in range(T):
            s = int(path[t])
            if s % 2 == 0:
                continue
            w = owner[(s - 1) // 2]
            if res[w] is None:
                res[w] = [t, t, 0]
            res[w][1] = t
            res[w][2] += 1
        return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--clips", required=True)
    ap.add_argument("--log", required=True)
    ap.add_argument("--session-start", required=True,
                    help="horodatage exact de la ligne BUILD de la session")
    args = ap.parse_args()

    al = Aligner()
    audio, bounds = load_clips(args.clips)
    exp = expected_words(args.log, args.session_start)
    idx = sorted(exp)
    print(f"audio concatene : {len(audio)/SR:.1f}s sur {len(bounds)} clips")
    print(f"mots attendus lus dans le log : {len(idx)} "
          f"(de {idx[0]} a {idx[-1]})")

    inconnus = [i for i in idx if exp[i] not in al.wtok]
    print(f"mots absents de word_tokens.json : {len(inconnus)}"
          + (f" -> {[exp[i] for i in inconnus[:5]]}" if inconnus else ""))
    kept = [i for i in idx if exp[i] in al.wtok]
    toks = [al.wtok[exp[i]] for i in kept]

    # ── FENETRES AVEC ANCRE QUI AVANCE ───────────────────────────────────────
    # BUG CORRIGE (2026-07-27) : la premiere version donnait les 239 mots comme
    # cible a CHAQUE fenetre. La DP part toujours du token 0, donc chaque
    # fenetre re-tentait les premiers mots du passage sur un audio qui contenait
    # les mots du milieu -- resultat : 8 mots places sur 239. Il faut faire
    # avancer une ancre, exactement comme BufferedTranscriber cote app.
    #
    # Chaque fenetre ne recoit donc que TARGET_WORDS mots a partir de l'ancre,
    # et l'ancre avance ensuite jusqu'au dernier mot place EN RETRAIT du bord
    # droit (BACKOFF) : les mots du bord sont laisses a la fenetre suivante, ou
    # ils seront interieurs. C'est ce recouvrement qui recolle les mots coupes.
    TARGET_WORDS = 40
    BACKOFF = 2
    win = int(WINDOW_S * SR)
    hop = int((WINDOW_S - OVERLAP_S) * SR)
    best = {}                     # mot -> (marge au bord, premiere, derniere, frames)
    anchor = 0
    for start in range(0, max(1, len(audio) - int(OVERLAP_S * SR)), hop):
        if anchor >= len(kept):
            break
        seg = audio[start:start + win]
        if len(seg) < SR:
            continue
        lp = al.logprobs(seg)
        sub = toks[anchor:anchor + TARGET_WORDS]
        res = al.align(lp, sub)
        if res is None:
            continue
        nF = lp.shape[0]
        places = [k for k, r in enumerate(res) if r is not None]
        for k in places:
            f0, f1, nf = res[k]
            marge = min(f0, nF - 1 - f1)      # distance au bord de la fenetre
            w = kept[anchor + k]
            if w not in best or marge > best[w][0]:
                best[w] = (marge, f0, f1, nf)
        # Avance de l'ancre : jusqu'au dernier mot place, moins le retrait.
        if places:
            anchor += max(1, places[-1] + 1 - BACKOFF)
        print(f"  fenetre {start/SR:6.1f}s : {len(places):>2} mots places, "
              f"ancre -> {anchor} (mot {kept[min(anchor, len(kept)-1)]})", flush=True)

    print(f"\n=== RESULTAT : {len(best)}/{len(kept)} mots mesures ===")
    etendue = [(v[2] - v[1] + 1) for v in best.values()]
    nonblank = [v[3] for v in best.values()]
    if not etendue:
        print("aucun mot mesure")
        return
    et = np.array(etendue); nb = np.array(nonblank)
    print(f"ETENDUE  (derniere-premiere+1, silences internes inclus) :")
    print(f"  median={np.median(et):.0f} frames (~{np.median(et)*MS_PER_FRAME:.0f}ms)"
          f"  p10={np.percentile(et,10):.0f}  p90={np.percentile(et,90):.0f}"
          f"  min={et.min()}  max={et.max()}")
    print(f"FRAMES NON-BLANK (ce que la DP etiquette, grandeur du plancher actuel) :")
    print(f"  median={np.median(nb):.0f} (~{np.median(nb)*MS_PER_FRAME:.0f}ms)"
          f"  p10={np.percentile(nb,10):.0f}  p90={np.percentile(nb,90):.0f}")
    print(f"\nrapport etendue/non-blank : median x{np.median(et/nb):.2f}")
    print(f"part des frames etiquetees : {100*nb.sum()/et.sum():.0f}%")
    out = {str(w): {"mot": exp[w], "etendue": int(v[2]-v[1]+1), "nonblank": int(v[3])}
           for w, v in sorted(best.items())}
    dest = Path(args.clips) / "durees_mesurees.json"
    json.dump(out, open(dest, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"\ndetail par mot -> {dest}")


if __name__ == "__main__":
    main()
