"""Test du modele 2 tetes sur une SOURATE ENTIERE recitee par un
professionnel (2026-07-22) -- controle demande par l'utilisateur.

Pour chaque verset (fichier <reciter>/90_<n>.wav) :
  - decode la tete lettres (CTC greedy, decoupage par mot via le marqueur
    BPE de debut de mot '▁'), avec les bornes de frame de chaque mot
  - decode la tete tajwid (CTC greedy, avec la frame de chaque emission)
  - attribue chaque regle detectee au mot dont l'intervalle de frames la
    contient (meme logique que ForcedAligner.kt cote app)
  - compare au texte tagge de reference (data/quran_tajweed_rules/
    uthmani_tajweed.jsonl) qui donne les regles ATTENDUES par mot
  - imprime, PAR MOT, attendu vs detecte, et signale les ecarts
    (regle manquante / regle en trop)

Usage :
  PYTHONPATH=... python3.14 test_dual_head_full_surah.py <surah> <reciter_dir> [reciter_dir2 ...]
  ex: ... test_dual_head_full_surah.py 90 Yasser_Ad-Dussary_128kbps MustaphaLahouni_assajda
"""
import os, sys, json, re
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"

import torch
import torch.nn as nn
import soundfile as sf
import nemo.collections.asr as nemo_asr
from pathlib import Path

BASE = Path(__file__).parent
NEMO_PATH = BASE / "models/fastconformer-dual-head-v1/stageb-convhead-v1/stageb-final.nemo"
HEAD_PATH = BASE / "models/fastconformer-dual-head-v1/stageb-convhead-v1/stageb-tajwid-head.pt"
TAJWID_HEAD_HIDDEN = 256
TAGGED_JSONL = BASE / "data/quran_tajweed_rules/uthmani_tajweed.jsonl"
WAV_ROOT = BASE / "data/train_wav_local"

RULE_CLASSES = [
    "madda_necessary", "madda_obligatory", "madda_permissible", "madda_normal",
    "ghunnah", "ikhafa", "ikhafa_shafawi", "idgham_ghunnah", "idgham_shafawi",
    "iqlab", "idgham_wo_ghunnah", "idgham_mutajanisayn", "idgham_mutaqaribayn",
    "laam_shamsiyah", "ham_wasl", "slnt", "qalaqah",
]
N_RULES = len(RULE_CLASSES)

class _Zero(nn.Module):
    def forward(self, lp, t, il, tl):
        return lp.sum() * 0.0


FULL_TAG_RE = re.compile(r'<tajweed\s+class=["\']?([a-z_]+)["\']?>(.*?)</tajweed>', re.S)
ANY_TAG_RE = re.compile(r"<[^>]+>")


def _strip_tags_with_spans(tagged):
    """Texte plat (tags retires) + [(start, end, classe)] en offsets du texte
    plat -- identique a build_rules_annotated_corpus.py, pour rester
    coherent avec la convention d'ancrage utilisee cote donnees d'entrainement
    et app (cf. correctif 2026-07-22 : symbole ancre au mot PRECEDENT quand le
    tag traverse une frontiere de mot, jamais duplique sur les deux)."""
    # Bug corrige 2026-07-23 (detecte via le test audio continu -- masque par
    # hasard dans le test par clips separes, ou la troncature au plus court
    # par verset avalait silencieusement ce dernier "mot" fantome) : le
    # numero de fin de verset (chiffres arabes-indiens, ex. <span
    # class=end>٥</span>) n'est JAMAIS recite -- ANY_TAG_RE ne retire que les
    # balises, pas leur contenu, donc ce chiffre restait comme un faux mot
    # attendu. Sur un test par verset isole, min(detecte,attendu) l'ignorait
    # silencieusement en fin de liste ; sur l'audio continu (pas de reset par
    # verset), il decalait TOUS les mots suivants en cascade. Retire ici,
    # antes tout traitement des tags de regle.
    tagged = re.sub(r"<span class=end>.*?</span>", "", tagged)
    flat = []
    spans = []
    pos = 0
    idx = 0
    for m in FULL_TAG_RE.finditer(tagged):
        before = ANY_TAG_RE.sub("", tagged[idx:m.start()])
        flat.append(before)
        pos += len(before)
        content = ANY_TAG_RE.sub("", m.group(2))
        spans.append((pos, pos + len(content), m.group(1)))
        flat.append(content)
        pos += len(content)
        idx = m.end()
    tail = ANY_TAG_RE.sub("", tagged[idx:])
    flat.append(tail)
    return "".join(flat), spans


def load_expected_words(surah):
    verses = {}
    with open(TAGGED_JSONL) as f:
        for line in f:
            d = json.loads(line)
            s, a = d["verse_key"].split(":")
            if int(s) == surah:
                verses[int(a)] = d["text"]
    words_all = []  # list of (verse, word_text_clean, set(classes))
    for a in sorted(verses):
        flat, spans = _strip_tags_with_spans(verses[a])
        for ent, ch in [("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")]:
            flat = flat.replace(ent, ch)
        word_bounds = []  # (start, end) char offsets of each word in `flat`
        i = 0
        n = len(flat)
        while i < n:
            while i < n and flat[i].isspace():
                i += 1
            if i >= n:
                break
            j = i
            while j < n and not flat[j].isspace():
                j += 1
            word_bounds.append((i, j))
            i = j
        word_classes = [set() for _ in word_bounds]

        def word_index_at(offset):
            for wi, (s, e) in enumerate(word_bounds):
                if s <= offset <= e:
                    return wi
            return len(word_bounds) - 1

        for start, end, cls in spans:
            content = flat[start:end]
            ws = content.find(" ")
            # Ancrage = debut du span (mot qui porte le caractere taggue), cf.
            # build_rules_annotated_corpus.py -- le cas special ham_wasl (ancre
            # au mot precedent) a ete ANNULE le 2026-07-23 apres mesure sur
            # l'alignement force reel (delta=0 : ham_wasl reste sur le mot du ٱ,
            # mot suivant).
            anchor = start + ws if ws != -1 else max(start, end - 1)
            wi = word_index_at(anchor)
            word_classes[wi].add(cls)

        for (s, e), cls in zip(word_bounds, word_classes):
            words_all.append((a, flat[s:e], cls))
    return words_all


@torch.no_grad()
def process_clip(m, head, blank, path):
    a, sr = sf.read(str(path), dtype="float32")
    if a.ndim > 1:
        a = a.mean(axis=1)
    if sr != 16000:
        import librosa
        a = librosa.resample(a, orig_sr=sr, target_sr=16000)
    dev = next(m.parameters()).device
    at = torch.tensor(a, device=dev).unsqueeze(0)
    lt = torch.tensor([a.shape[0]], dtype=torch.int64, device=dev)
    feats, flen = m.preprocessor(input_signal=at, length=lt)
    enc, _ = m.encoder(audio_signal=feats, length=flen)

    letters_logits = m.ctc_decoder(encoder_output=enc)
    letters_ids = letters_logits[0].argmax(-1).tolist()

    # segmente les frames en mots : nouveau mot quand un token qui commence
    # par le marqueur BPE de debut de mot ('▁') est emis (greedy, blancs sautes)
    words = []  # list of dict(text, first_frame, last_frame)
    cur_ids = []
    cur_first = None
    prev = -1
    for fi, tid in enumerate(letters_ids):
        if tid == blank:
            prev = tid
            continue
        if tid == prev:
            continue
        prev = tid
        piece = m.tokenizer.ids_to_tokens([tid])[0]
        starts_word = piece.startswith("▁")
        if starts_word and cur_ids:
            words.append({"ids": cur_ids, "first": cur_first, "last": fi - 1})
            cur_ids = []
            cur_first = None
        if cur_first is None:
            cur_first = fi
        cur_ids.append(tid)
    if cur_ids:
        words.append({"ids": cur_ids, "first": cur_first, "last": len(letters_ids) - 1})
    for w in words:
        w["text"] = m.tokenizer.ids_to_text(w["ids"])

    tajwid_logits = head(enc.transpose(1, 2))
    tajwid_ids = tajwid_logits[0].argmax(-1).tolist()
    detected = []  # (frame, rule_name)
    tprev = -1
    for fi, tid in enumerate(tajwid_ids):
        if tid == N_RULES:
            tprev = tid
            continue
        if tid == tprev:
            continue
        tprev = tid
        detected.append((fi, RULE_CLASSES[tid]))

    for w in words:
        w["detected"] = set(r for fr, r in detected if w["first"] <= fr <= w["last"])
    return words


def main():
    surah = int(sys.argv[1])
    reciters = sys.argv[2:]
    expected = load_expected_words(surah)

    m = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        str(NEMO_PATH), map_location="cpu")
    if hasattr(m, "joint"):
        m.joint.set_fuse_loss_wer(False, loss=None, metric=None)
    m.loss = _Zero()
    m.eval()
    if torch.cuda.is_available():
        m = m.cuda()
    dev = next(m.parameters()).device

    if TAJWID_HEAD_HIDDEN > 0:
        from finetune_dual_head import ConvTajwidHead
        head = ConvTajwidHead(m.encoder._feat_out, TAJWID_HEAD_HIDDEN, N_RULES + 1).to(dev)
    else:
        head = nn.Linear(m.encoder._feat_out, N_RULES + 1).to(dev)
    head.load_state_dict(torch.load(HEAD_PATH, map_location=dev))
    head.eval()
    blank = m.tokenizer.vocab_size

    n_verses = max(a for a, _, _ in expected)

    for reciter in reciters:
        print(f"\n{'='*70}\nRECITATEUR : {reciter}\n{'='*70}")
        all_words = []
        for a in range(1, n_verses + 1):
            clip = WAV_ROOT / reciter / f"{surah}_{a}.wav"
            if not clip.exists():
                print(f"  [verset {a}] fichier absent : {clip}")
                continue
            words = process_clip(m, head, blank, clip)
            exp_this_verse = [(w, cls) for (av, w, cls) in expected if av == a]
            n = min(len(words), len(exp_this_verse))
            if len(words) != len(exp_this_verse):
                print(f"  [verset {a}] DESALIGNEMENT nb mots : detecte={len(words)} attendu={len(exp_this_verse)}")
            for k in range(n):
                exp_w, exp_cls = exp_this_verse[k]
                det_cls = words[k]["detected"]
                all_words.append((a, k, exp_w, words[k]["text"], exp_cls, det_cls))

        idx = 0
        n_err_words = 0
        for (a, k, exp_w, det_txt, exp_cls, det_cls) in all_words:
            idx += 1
            missing = exp_cls - det_cls
            extra = det_cls - exp_cls
            if missing or extra:
                n_err_words += 1
                flags = []
                if missing:
                    flags.append(f"MANQUANT={sorted(missing)}")
                if extra:
                    flags.append(f"EN_TROP={sorted(extra)}")
                print(f"  mot#{idx:3d} verset={a:2d} \"{exp_w}\" (lettres detectees: \"{det_txt}\") "
                      f"attendu={sorted(exp_cls) or '-'} detecte={sorted(det_cls) or '-'}  <<< {' '.join(flags)}")
        print(f"  --- total mots={idx}, mots avec ecart={n_err_words} ({100*n_err_words/max(idx,1):.1f}%) ---")


if __name__ == "__main__":
    main()
