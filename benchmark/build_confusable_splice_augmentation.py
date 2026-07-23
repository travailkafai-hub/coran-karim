"""
Augmentation de corpus par MONTAGE AUDIO de lettres confusables (tajweed
classique, makharij proches) -- FONCTIONNALITES_FUTURES.md section 8bis,
2026-07-14. "Chemin inverse" (idee utilisateur) : au lieu d'enregistrer ou
de synthetiser (TTS) de nouvelles fautes, reutilise l'alignement forcé CTC
(fiabilise le meme jour, cf. ForcedAligner.kt/MIN_FRAMES_FOR_JUDGMENT) pour
reperer les frontieres EXACTES (en frames) d'une lettre precise dans l'audio
DEJA existant (284k clips, 54 recitateurs), puis SPLICE un segment reel
(contenant la lettre confusable, dit par un vrai humain ailleurs dans le
corpus) a la place -- fabrique une "faute" composee a 100% de vraie voix,
sans enregistrer une seule nouvelle prise.

Etiquette du resultat = texte REELLEMENT obtenu apres montage (avec la
lettre substituee), jamais le texte canonique -- meme principe que le
corpus d'erreurs delibérées (§8) et la calibration voix (§8ter).

Conversion frame -> echantillon : window_stride=0.01s, subsampling_factor=8
(verifie sur le modele tajweed, 2026-07-14) -> 1280 echantillons/frame a
16kHz (80ms/frame).

STATUT : outil construit et teste sur UN exemple (mode --demo). PAS encore
utilise pour un reentrainement complet -- ecouter plusieurs exemples generes
avant de lancer une augmentation a grande echelle (risque d'artefact au
point de raccord, cf. §8bis "Risque principal").

Usage (demo, un seul exemple, ecrit le WAV resultant pour ecoute manuelle) :
    .venv_nemo/bin/python build_confusable_splice_augmentation.py --demo
"""
import os, json, random, argparse
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import numpy as np
import torch
import soundfile as sf
import nemo.collections.asr as nemo_asr
import onnxruntime as ort
from pathlib import Path

BASE_DIR = Path(__file__).parent
NEMO_PATH = BASE_DIR / "models" / "fastconformer-quran-tajweed" / "fastconformer-quran-best.nemo"
ONNX_PATH = BASE_DIR / "models" / "fastconformer-quran-tajweed" / "deploy" / "fastconformer-ctc-tajweed" / "model.onnx"
VOCAB_PATH = BASE_DIR / "models" / "fastconformer-quran-tajweed" / "deploy" / "fastconformer-ctc-tajweed" / "vocab.json"
MANIFEST = BASE_DIR / "nemo_manifests_tajweed" / "train_manifest.jsonl"

SAMPLE_RATE = 16000
SAMPLES_PER_FRAME = 1280  # window_stride=0.01s * subsampling_factor=8 * 16000Hz

# Paires confusables (tajweed classique, makharij proches) -- meme table que
# app/lib/data/voice_calibration_words.dart (§8ter), pour usage corpus ici.
CONFUSABLE_PAIRS = [
    ("ص", "س"), ("س", "ص"),
    ("ط", "ت"), ("ت", "ط"),
    ("ض", "د"), ("د", "ض"),
    ("ذ", "ز"), ("ز", "ذ"),
    ("ح", "ه"), ("ه", "ح"),
    ("ق", "ك"), ("ك", "ق"),
    ("ع", "ء"), ("ء", "ع"),
    ("خ", "ح"), ("ح", "خ"),
]


class EncCTCWrapper(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.encoder = model.encoder
        self.ctc_decoder = model.ctc_decoder

    def forward(self, audio_signal, length):
        encoded, encoded_len = self.encoder(audio_signal=audio_signal, length=length)
        logits = self.ctc_decoder(encoder_output=encoded)
        return torch.nn.functional.log_softmax(logits, dim=-1)


def load_everything():
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(NEMO_PATH), map_location="cpu")
    model.eval()
    model.preprocessor.featurizer.dither = 0.0
    tok = model.tokenizer
    vocab = json.load(open(VOCAB_PATH, encoding="utf-8"))
    blank_id = len(vocab)
    sess = ort.InferenceSession(str(ONNX_PATH), providers=["CPUExecutionProvider"])
    return model, tok, vocab, blank_id, sess


def compute_logprobs(model, sess, audio_np):
    audio_t = torch.tensor(audio_np).unsqueeze(0)
    len_t = torch.tensor([audio_np.shape[0]], dtype=torch.int64)
    feats, feats_len = model.preprocessor(input_signal=audio_t, length=len_t)
    out = sess.run(["logprobs"], {
        "audio_signal": feats.numpy().astype(np.float32),
        "length": feats_len.numpy().astype(np.int64),
    })[0]
    return out[0]  # [T, vocab+1]


def forced_align_tokens(logprobs, flat_tokens, blank_id):
    """DP d'alignement force CTC standard (meme algorithme que ForcedAligner.kt) --
    retourne, pour chaque token de [flat_tokens], sa plage de frames [first, last]
    (None si jamais atteint dans le meilleur chemin partiel)."""
    t = logprobs.shape[0]
    n = len(flat_tokens)
    s = 2 * n + 1
    neg = float("-inf")

    def emit(ti, si):
        return logprobs[ti][blank_id] if si % 2 == 0 else logprobs[ti][flat_tokens[(si - 1) // 2]]

    prev = np.full(s, neg)
    prev[0] = emit(0, 0)
    if s > 1:
        prev[1] = emit(0, 1)
    bp = np.zeros((t, s), dtype=np.int8)

    for ti in range(1, t):
        cur = np.full(s, neg)
        for si in range(s):
            best = prev[si]
            frm = 0
            if si >= 1 and prev[si - 1] > best:
                best = prev[si - 1]; frm = 1
            if si >= 3 and si % 2 == 1 and flat_tokens[(si - 1) // 2] != flat_tokens[(si - 3) // 2] and prev[si - 2] > best:
                best = prev[si - 2]; frm = 2
            cur[si] = neg if best == neg else best + emit(ti, si)
            bp[ti][si] = frm
        prev = cur

    best_end = int(np.argmax(prev))
    if prev[best_end] == neg:
        return None

    path = np.zeros(t, dtype=np.int32)
    si_cur = best_end
    for ti in range(t - 1, -1, -1):
        path[ti] = si_cur
        if ti > 0:
            si_cur -= bp[ti][si_cur]

    first_frame = [-1] * n
    last_frame = [-1] * n
    for ti in range(t):
        si = path[ti]
        if si % 2 == 0:
            continue
        tok_idx = (si - 1) // 2
        if first_frame[tok_idx] < 0:
            first_frame[tok_idx] = ti
        last_frame[tok_idx] = ti
    return first_frame, last_frame


def find_letter_token_span(tok, word, letter):
    """Retourne (start_tok_idx, end_tok_idx, ids) : le sous-ensemble de tokens
    BPE du mot dont la CONCATENATION des pieces contient exactement [letter]
    (recherche le plus petit segment de tokens contigus qui couvre la lettre --
    en general 1 seul token, les pieces BPE etant courtes cote tajweed)."""
    ids = tok.text_to_ids(word)
    pieces = tok.ids_to_tokens(ids)
    # reconstruit les positions caracteres de chaque piece dans le mot decode
    pos = 0
    spans = []  # (char_start, char_end, tok_idx)
    for i, p in enumerate(pieces):
        clean = p.lstrip("▁")
        spans.append((pos, pos + len(clean), i))
        pos += len(clean)
    full = "".join(p.lstrip("▁") for p in pieces)
    idx = full.find(letter)
    if idx < 0:
        return None
    matching = [i for (a, b, i) in spans if a <= idx < b]
    if not matching:
        return None
    return ids, matching[0], matching[0]


def extract_segment(model, sess, audio_path, word, letter, tok):
    """Charge le clip, aligne le MOT SEUL (pas toute la phrase -- suffisant
    et bien plus rapide) sur son propre segment audio, retourne les
    echantillons couvrant [letter] dans ce mot."""
    audio_np, sr = sf.read(audio_path, dtype="float32")
    assert sr == SAMPLE_RATE
    logprobs = compute_logprobs(model, sess, audio_np)
    res = find_letter_token_span(tok, word, letter)
    if res is None:
        return None
    ids, tok_start, tok_end = res
    align = forced_align_tokens(logprobs, ids, len(json.load(open(VOCAB_PATH, encoding="utf-8"))))
    if align is None:
        return None
    first_frame, last_frame = align
    f0, f1 = first_frame[tok_start], last_frame[tok_end]
    if f0 < 0 or f1 < 0:
        return None
    s0 = f0 * SAMPLES_PER_FRAME
    s1 = min((f1 + 1) * SAMPLES_PER_FRAME, len(audio_np))
    return audio_np[s0:s1]


def splice(target_audio, target_word, target_letter, source_segment, crossfade_samples=160):
    """Remplace, dans [target_audio], la portion correspondant a la PREMIERE
    occurrence de [target_letter] dans [target_word] (memes conventions que
    extract_segment) par [source_segment] -- avec un court fondu (10ms par
    defaut) aux deux jointures pour attenuer le clic de raccord."""
    raise NotImplementedError(
        "Necessite le meme alignement que extract_segment sur target_audio -- "
        "cf. demo() pour l'usage complet bout-en-bout, cette fonction seule "
        "sert de reference d'API, appelee depuis demo()."
    )


def demo():
    print("Chargement modele/tokenizer/ONNX...")
    model, tok, vocab, blank_id, sess = load_everything()

    rows = [json.loads(l) for l in open(MANIFEST, encoding="utf-8")]
    random.seed(3)

    # Mot de reference lu depuis voice_calibration_words.dart (deja genere
    # programmatiquement depuis l'API le 2026-07-14, bytes garantis exacts --
    # evite de retaper l'arabe a la main, piege deja rencontre plusieurs fois
    # cette session) : la paire ٱلنَّاسِ/ٱلنَّاصِ (س/ص, An-Nas 114:1).
    dart_src = (BASE_DIR.parent / "app" / "lib" / "data" / "voice_calibration_words.dart").read_text(encoding="utf-8")
    import re
    m = re.search(r'correct:\s*"([^"]*)",\s*\n\s*wrong:\s*"([^"]*)",\s*\n\s*targetLetter:\s*"([^"]*)",\s*\n\s*confusedLetter:\s*"([^"]*)",\s*\n\s*reference:\s*"An-Nas 114:1"', dart_src)
    if not m:
        print("Paire An-Nas 114:1 introuvable dans voice_calibration_words.dart")
        return
    ref_correct, ref_wrong, letter_target, letter_confused = m.groups()
    print(f"Mot de reference (depuis Dart) : {ref_correct!r} (lettre {letter_target} -> {letter_confused})")

    # Cherche un clip cible contenant ce mot exact.
    target_word = None
    target_row = None
    for r in rows:
        for w in r["text"].split():
            if w == ref_correct:
                target_word = w
                target_row = r
                break
        if target_row:
            break
    if not target_row:
        print("Mot cible introuvable dans le manifest, ajuste la recherche.")
        return
    print("Clip cible :", target_row["audio_filepath"], "mot:", target_word)

    source_row = None
    source_word = None
    for r in rows[:20000]:
        if letter_confused in r["text"] and r["audio_filepath"] != target_row["audio_filepath"]:
            for w in r["text"].split():
                if letter_confused in w and len(w) <= 8:
                    source_row = r
                    source_word = w
                    break
        if source_row:
            break
    if not source_row:
        print("Clip source introuvable.")
        return
    print("Clip source :", source_row["audio_filepath"], "mot:", source_word)

    print(f"Extraction du segment source (lettre {letter_confused})...")
    src_seg = extract_segment(model, sess, source_row["audio_filepath"], source_word, letter_confused, tok)
    if src_seg is None:
        print("Echec extraction segment source.")
        return
    print(f"  segment source : {len(src_seg)/SAMPLE_RATE:.3f}s")

    print(f"Alignement de la cible pour reperer le {letter_target} a remplacer...")
    target_audio, sr = sf.read(target_row["audio_filepath"], dtype="float32")
    logprobs = compute_logprobs(model, sess, target_audio)
    res = find_letter_token_span(tok, target_word, letter_target)
    if res is None:
        print(f"Lettre {letter_target} introuvable dans le decoupage BPE du mot cible.")
        return
    ids, tok_start, tok_end = res
    align = forced_align_tokens(logprobs, ids, blank_id)
    if align is None:
        print("Echec alignement cible.")
        return
    first_frame, last_frame = align
    f0, f1 = first_frame[tok_start], last_frame[tok_end]
    if f0 < 0 or f1 < 0:
        print("Frontiere non trouvee pour la lettre cible.")
        return
    s0 = f0 * SAMPLES_PER_FRAME
    s1 = min((f1 + 1) * SAMPLES_PER_FRAME, len(target_audio))
    print(f"  segment cible a remplacer : frames [{f0},{f1}] -> echantillons [{s0},{s1}] ({(s1-s0)/SAMPLE_RATE:.3f}s)")

    # Montage avec fondu croise court (10ms) aux 2 jointures.
    fade = min(160, len(src_seg) // 4, s0, len(target_audio) - s1)
    fade = max(fade, 0)
    out = np.concatenate([
        target_audio[:s0 - fade] if fade else target_audio[:s0],
        _crossfade(target_audio[s0 - fade:s0], src_seg[:fade], fade) if fade else src_seg[:0],
        src_seg[fade:len(src_seg) - fade] if fade else src_seg,
        _crossfade(src_seg[len(src_seg) - fade:], target_audio[s1:s1 + fade], fade) if fade else target_audio[s1:s1],
        target_audio[s1 + fade:],
    ])

    wrong_word = target_word.replace(letter_target, letter_confused, 1)
    wrong_text = target_row["text"].replace(target_word, wrong_word, 1)

    out_dir = BASE_DIR / "scratch_splice_demo"
    out_dir.mkdir(exist_ok=True)
    out_path = out_dir / "demo_spliced.wav"
    sf.write(out_path, out, SAMPLE_RATE)
    print(f"\nEcrit : {out_path}")
    print("Texte original :", target_row["text"])
    print("Texte apres montage (etiquette) :", wrong_text)
    print("\n-> Ecouter ce fichier pour valider l'absence d'artefact grossier avant toute augmentation a grande echelle.")


def _crossfade(a, b, n):
    if n <= 0 or len(a) < n or len(b) < n:
        return np.concatenate([a, b])[:max(len(a), len(b))]
    ramp = np.linspace(0, 1, n, dtype=np.float32)
    return a[:n] * (1 - ramp) + b[:n] * ramp


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--demo", action="store_true", help="Fabrique UN exemple et l'ecrit pour ecoute manuelle")
    args = p.parse_args()
    if args.demo:
        demo()
    else:
        print("Utilise --demo pour un premier exemple. Pas encore de mode augmentation a grande echelle (a construire apres validation).")
