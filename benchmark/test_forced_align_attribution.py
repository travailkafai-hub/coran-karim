"""Reproduit l'attribution de regles tajwid de PRODUCTION (2026-07-23).

L'app n'utilise PAS le decoupage greedy libre (ce que faisait
test_dual_head_full_surah.py) mais un ALIGNEMENT FORCE Viterbi CTC du texte
cible (lettres nu) contre la tete 1, puis attribue chaque regle detectee par
la tete 2 au mot dont la fenetre de frames (issue de l'alignement force) la
contient. C'est EXACTEMENT ForcedAligner.kt.

Ces deux pipelines segmentent les mots differemment aux frontieres, donc
attribuent les regles de jonction (ham_wasl / iqlab / idgham / ikhafa) a des
mots potentiellement DIFFERENTS. Mes correctifs "mot precedent" (annotated.
jsonl) ont ete valides contre le greedy libre -- ce script verifie s'ils sont
corrects pour le pipeline REEL (alignement force).

Pour chaque clip verset :
  - aligne (Viterbi CTC) les tokens du texte nu contre la tete 1
  - deduit la fenetre de frames de chaque mot
  - decode la tete 2 -> (frame, regle)
  - attribue chaque regle au mot dont la fenetre la contient
  - imprime, pour chaque regle de jonction, sur quel MOT (index) elle tombe
    -> permet de savoir si l'attendu doit etre sur le mot precedent ou suivant

Usage :
  PYTHONPATH=... python3.14 test_forced_align_attribution.py <surah> <reciter_dir> [reciter_dir2 ...]
"""
import os, sys, json, re
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"

import math
import torch
import torch.nn as nn
import numpy as np
import soundfile as sf
import nemo.collections.asr as nemo_asr
from pathlib import Path

BASE = Path(__file__).parent
NEMO_PATH = BASE / "models/fastconformer-dual-head-v1/stageb-convhead-v1/stageb-final.nemo"
HEAD_PATH = BASE / "models/fastconformer-dual-head-v1/stageb-convhead-v1/stageb-tajwid-head.pt"
TAGGED_JSONL = BASE / "data/quran_tajweed_rules/uthmani_tajweed.jsonl"
WAV_ROOT = BASE / "data/train_wav_local"

RULE_CLASSES = [
    "madda_necessary", "madda_obligatory", "madda_permissible", "madda_normal",
    "ghunnah", "ikhafa", "ikhafa_shafawi", "idgham_ghunnah", "idgham_shafawi",
    "iqlab", "idgham_wo_ghunnah", "idgham_mutajanisayn", "idgham_mutaqaribayn",
    "laam_shamsiyah", "ham_wasl", "slnt", "qalaqah",
]
N_RULES = len(RULE_CLASSES)
JUNCTION_RULES = {"ham_wasl", "iqlab", "idgham_ghunnah", "idgham_wo_ghunnah",
                  "ikhafa", "ikhafa_shafawi", "idgham_shafawi",
                  "idgham_mutajanisayn", "idgham_mutaqaribayn", "laam_shamsiyah"}

FULL_TAG_RE = re.compile(r'<tajweed\s+class=["\']?([a-z_]+)["\']?>(.*?)</tajweed>', re.S)
ANY_TAG_RE = re.compile(r"<[^>]+>")


class _Zero(nn.Module):
    def forward(self, lp, t, il, tl):
        return lp.sum() * 0.0


def strip_pua(t):
    return "".join(c for c in t if not (0xE000 <= ord(c) <= 0xF8FF))


def load_verse_words(surah):
    """Retourne {ayah: [(mot_nu, set(classes_de_jonction_avec_leur_position))]}.
    On garde AUSSI, pour chaque tag de jonction, l'index du mot precedent et
    du mot suivant tels que le texte les decoupe, pour l'analyse."""
    verses = {}
    with open(TAGGED_JSONL) as f:
        for line in f:
            d = json.loads(line)
            s, a = d["verse_key"].split(":")
            if int(s) != surah:
                continue
            tagged = re.sub(r"<span class=end>.*?</span>", "", d["text"])
            # texte plat + spans (offsets)
            flat, spans = [], []
            pos, idx = 0, 0
            for m in FULL_TAG_RE.finditer(tagged):
                before = ANY_TAG_RE.sub("", tagged[idx:m.start()])
                flat.append(before); pos += len(before)
                content = ANY_TAG_RE.sub("", m.group(2))
                spans.append((pos, pos + len(content), m.group(1)))
                flat.append(content); pos += len(content)
                idx = m.end()
            flat.append(ANY_TAG_RE.sub("", tagged[idx:]))
            flat = "".join(flat)
            for ent, ch in [("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")]:
                flat = flat.replace(ent, ch)
            # bornes de mots
            wb = []
            i, nn_ = 0, len(flat)
            while i < nn_:
                while i < nn_ and flat[i].isspace():
                    i += 1
                if i >= nn_:
                    break
                j = i
                while j < nn_ and not flat[j].isspace():
                    j += 1
                wb.append((i, j)); i = j
            words = [flat[s0:e0] for s0, e0 in wb]

            def widx(off):
                for k, (s0, e0) in enumerate(wb):
                    if s0 <= off <= e0:
                        return k
                return len(wb) - 1

            # pour chaque tag de jonction : mot ou commence le tag (trigger) et
            # mot ou finit le tag
            junctions = []  # (cls, word_start, word_end_of_span, crosses_space)
            for st, en, cls in spans:
                content = flat[st:en]
                crosses = " " in content
                junctions.append((cls, widx(st), widx(max(st, en - 1)), crosses))
            verses[int(a)] = (words, junctions)
    return verses


def ctc_forced_align(scoring_lp, flat, blank_id):
    """Viterbi CTC forced alignment -- miroir de ForcedAligner.kt.
    Retourne path[t] = etat, et par-mot (via owner) les bornes de frames."""
    t = len(scoring_lp)
    n = len(flat)
    s = 2 * n + 1
    NEG = -1e30
    prev = np.full(s, NEG)
    bp = np.zeros((t, s), dtype=np.int8)

    def emit(ti, si):
        if si % 2 == 0:
            return scoring_lp[ti][blank_id]
        return scoring_lp[ti][flat[(si - 1) // 2]]

    prev[0] = emit(0, 0)
    if s > 1:
        prev[1] = emit(0, 1)
    cur = np.full(s, NEG)
    for ti in range(1, t):
        cur[:] = NEG
        for si in range(s):
            best = prev[si]; frm = 0
            if si >= 1 and prev[si - 1] > best:
                best = prev[si - 1]; frm = 1
            if (si >= 3 and si % 2 == 1 and
                    flat[(si - 1) // 2] != flat[(si - 3) // 2] and
                    prev[si - 2] > best):
                best = prev[si - 2]; frm = 2
            cur[si] = NEG if best <= NEG / 2 else best + emit(ti, si)
            bp[ti][si] = frm
        prev, cur = cur.copy(), prev
    best_end = int(np.argmax(prev))
    # backtrace
    path = np.zeros(t, dtype=np.int32)
    si = best_end
    for ti in range(t - 1, -1, -1):
        path[ti] = si
        if ti > 0:
            si -= bp[ti][si]
    return path


@torch.no_grad()
def process(m, head, blank, wav, words, tokenizer):
    a, sr = sf.read(str(wav), dtype="float32")
    if a.ndim > 1:
        a = a.mean(axis=1)
    dev = next(m.parameters()).device
    at = torch.tensor(a, device=dev).unsqueeze(0)
    lt = torch.tensor([a.shape[0]], dtype=torch.int64, device=dev)
    feats, flen = m.preprocessor(input_signal=at, length=lt)
    enc, _ = m.encoder(audio_signal=feats, length=flen)
    letters_logits = m.ctc_decoder(encoder_output=enc)
    lp = torch.log_softmax(letters_logits[0], dim=-1).cpu().numpy()

    # tokens par mot (forme nu)
    word_tokens = []
    for w in words:
        toks = tokenizer.text_to_ids(w)
        word_tokens.append(toks)
    flat, owner = [], []
    for wi, toks in enumerate(word_tokens):
        for tk in toks:
            flat.append(tk); owner.append(wi)
    if not flat:
        return None
    path = ctc_forced_align(lp, flat, blank)

    W = len(words)
    first = [-1] * W
    last = [-1] * W
    for ti, si in enumerate(path):
        if si % 2 == 0:
            continue
        tok_idx = (si - 1) // 2
        wi = owner[tok_idx]
        if first[wi] < 0:
            first[wi] = ti
        last[wi] = ti

    # tete 2
    tajwid_logits = head(enc.transpose(1, 2))
    tids = tajwid_logits[0].argmax(-1).tolist()
    detected = []
    tprev = -1
    for fi, tid in enumerate(tids):
        if tid == N_RULES:
            tprev = tid; continue
        if tid == tprev:
            continue
        tprev = tid
        detected.append((fi, RULE_CLASSES[tid]))

    # attribution par fenetre de frame
    per_word = [set() for _ in range(W)]
    for fr, rule in detected:
        for wi in range(W):
            if first[wi] <= fr <= last[wi]:
                per_word[wi].add(rule)
                break
    return per_word, first, last


def main():
    surah = int(sys.argv[1])
    reciters = sys.argv[2:]
    verses = load_verse_words(surah)

    m = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        str(NEMO_PATH), map_location="cpu")
    if hasattr(m, "joint"):
        m.joint.set_fuse_loss_wer(False, loss=None, metric=None)
    m.loss = _Zero(); m.eval()
    if torch.cuda.is_available():
        m = m.cuda()
    dev = next(m.parameters()).device
    from finetune_dual_head import ConvTajwidHead
    head = ConvTajwidHead(m.encoder._feat_out, 256, N_RULES + 1).to(dev)
    head.load_state_dict(torch.load(HEAD_PATH, map_location=dev))
    head.eval()
    blank = m.tokenizer.vocab_size

    # comptage : pour chaque regle de jonction, atterrit-elle sur le mot qui
    # PORTE le trigger dans le texte (word_start du span) ou sur son voisin ?
    from collections import Counter
    verdict = {r: Counter() for r in JUNCTION_RULES}

    for reciter in reciters:
        for ayah, (words, junctions) in verses.items():
            wav = WAV_ROOT / reciter / f"{surah}_{ayah}.wav"
            if not wav.exists():
                continue
            res = process(m, head, blank, wav, words, m.tokenizer)
            if res is None:
                continue
            per_word, first, last = res
            for cls, wstart, wend, crosses in junctions:
                if cls not in JUNCTION_RULES:
                    continue
                # trouver ou la regle est REELLEMENT detectee (mot le plus proche)
                found = [wi for wi in range(len(words)) if cls in per_word[wi]]
                if not found:
                    verdict[cls]["non_detecte"] += 1
                    continue
                # le span va du mot wstart (trigger) au mot wend (souvent
                # wstart+1 si crosses). Note ou tombe la detection par rapport
                # a wstart (mot qui PORTE le caractere taggue).
                nearest = min(found, key=lambda wi: abs(wi - wstart))
                delta = nearest - wstart
                verdict[cls][f"delta={delta:+d}"] += 1

    print("\n=== Attribution PRODUCTION (alignement force) des regles de jonction ===")
    print("delta = mot_detecte - mot_qui_porte_le_caractere_taggue_dans_le_texte")
    print("(delta=0 : sur le trigger ; delta=+1 : mot suivant ; delta=-1 : mot precedent)\n")
    for r in sorted(verdict):
        c = verdict[r]
        if sum(c.values()) == 0:
            continue
        tot = sum(c.values())
        parts = ", ".join(f"{k}:{v}" for k, v in sorted(c.items()))
        print(f"  {r:<20} (n={tot})  {parts}")


if __name__ == "__main__":
    main()
