"""
youtube_align.py — aligne les audios YouTube sur les versets du Coran.

Stratégie (sans pipeline) :
  1. Découpe chaque m4a en blocs de 30 s via ffmpeg → float32 16kHz
  2. Transcrit chaque bloc avec model.generate() (API directe, aucun kwarg fragile)
  3. Sliding-window match : cherche la fenêtre de 1-8 versets consécutifs
     qui maximise la similarité caractère-niveau vs la transcription
  4. Si score > MATCH_THRESHOLD : sauvegarde le bloc WAV avec le texte
     canonique des versets correspondants

Le label texte = versets 1, 2, 3 … concaténés si plusieurs versets sont
dans le même bloc. C'est du training data valide pour Whisper (longueur
variable, bien en dessous de MAX_LABEL=440).

Bruit : 40 % des blocs sauvegardés sont augmentés (noise_augment).

Sortie :
  data/youtube_wav/{surah_dir}/{video_id}_{chunk_idx:04d}.wav
  data/manifest_youtube_aligned.jsonl
  data/train_combined.jsonl   (train_full.jsonl + YouTube)

Temps estimé : ~50-70 min pour 184 fichiers sur RTX 5080.
"""
import truststore; truststore.inject_into_ssl()

import json, re, subprocess, time
import numpy as np
import soundfile as sf
from difflib import SequenceMatcher
from pathlib import Path

ROOT       = Path(__file__).parent
YT_DIR     = ROOT / "data" / "youtube_audio"
OUT_DIR    = ROOT / "data" / "youtube_wav"
ALIGN_MAN  = ROOT / "data" / "manifest_youtube_aligned.jsonl"
TRAIN_ORIG = ROOT / "data" / "train_full.jsonl"
TRAIN_COMB = ROOT / "data" / "train_combined.jsonl"

MODEL_DIR  = str(ROOT / "models" / "whisper-phase4-noisy")
SR         = 16000

MATCH_THRESHOLD = 0.45   # fenêtre de 1-8 versets doit atteindre ce score
CHUNK_S    = 30          # durée de chaque bloc audio (secondes)
MAX_WIN    = 8           # taille maximale de la fenêtre de versets (nombre)
LOOKAHEAD  = 4           # blocs non-alignés avant d'avancer le pointeur versets
NOISE_PROB = 0.40        # 40 % des clips avec bruit ajouté


# ── Arabic normalization ──────────────────────────────────────────────────────

_HARAKAT = re.compile(r'[ً-ٰٟۖ-ۜ۟-۪ۤۧۨ-ۭ]')

def normalize(text: str) -> str:
    text = _HARAKAT.sub('', text)
    text = re.sub(r'ـ', '', text)     # tatweel
    text = text.replace('أ', 'ا').replace('إ', 'ا').replace('آ', 'ا')
    text = text.replace('ى', 'ي').replace('ؤ', 'و').replace('ئ', 'ي')
    text = re.sub(r'[^؀-ۿ\s]', '', text)
    return ' '.join(text.split()).strip()


def sim(hyp: str, ref: str) -> float:
    h, r = normalize(hyp), normalize(ref)
    if not h or not r:
        return 0.0
    return SequenceMatcher(None, h, r).ratio()


# ── Audio decoding ────────────────────────────────────────────────────────────

def decode_m4a(path: str) -> np.ndarray:
    cmd = ["ffmpeg", "-y", "-loglevel", "error",
           "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "pipe:1"]
    r = subprocess.run(cmd, capture_output=True, timeout=600)
    if r.returncode != 0 or len(r.stdout) < 4:
        raise RuntimeError(f"ffmpeg: {r.stderr[:200]}")
    return np.frombuffer(r.stdout, dtype=np.float32).copy()


# ── Verse database ────────────────────────────────────────────────────────────

def load_verse_db() -> dict[int, list[tuple[int, str]]]:
    db: dict[int, dict] = {}
    with open(TRAIN_ORIG, encoding="utf-8") as f:
        for line in f:
            r = json.loads(line)
            surah, ayah = map(int, r["key"].split(":"))
            db.setdefault(surah, {})[ayah] = r["text"]
    return {s: sorted(a.items()) for s, a in db.items()}


# ── Whisper model (loaded once) ───────────────────────────────────────────────

_model = None
_proc  = None
_device = None

def get_model():
    global _model, _proc, _device
    if _model is None:
        import torch
        from transformers import WhisperForConditionalGeneration, WhisperProcessor
        _device = "cuda" if torch.cuda.is_available() else "cpu"
        print(f"Chargement Whisper ({MODEL_DIR}) sur {_device.upper()}...", flush=True)
        _proc  = WhisperProcessor.from_pretrained(MODEL_DIR)
        _model = WhisperForConditionalGeneration.from_pretrained(MODEL_DIR).to(_device)
        _model.eval()
        # Fix outdated generation_config (missing is_multilingual in old checkpoints)
        forced_ids = _proc.get_decoder_prompt_ids(language="arabic", task="transcribe")
        _model.generation_config.is_multilingual    = True
        _model.generation_config.forced_decoder_ids = forced_ids
        _model.generation_config.suppress_tokens    = []
        _model.generation_config.max_length         = 448   # total; new tokens = max - 4 prompt
        print("  Charge.", flush=True)
    return _model, _proc, _device


def transcribe(seg: np.ndarray) -> str:
    """Transcrit un segment audio (≤ 30 s) → texte arabe."""
    import torch
    model, proc, device = get_model()
    feats = proc.feature_extractor(seg, sampling_rate=SR, return_tensors="pt").input_features
    feats = feats.to(device)
    with torch.no_grad():
        ids = model.generate(feats, max_new_tokens=440)
    return proc.tokenizer.decode(ids[0], skip_special_tokens=True).strip()


# ── Noise augmentation ────────────────────────────────────────────────────────

_aug_available = False
try:
    from noise_augment import random_augment
    _aug_available = True
except ImportError:
    pass

def maybe_augment(audio: np.ndarray) -> np.ndarray:
    if _aug_available:
        return random_augment(audio, sr=SR, prob=NOISE_PROB)
    return audio


# ── Alignment ─────────────────────────────────────────────────────────────────

def find_best_window(hyp: str, verses: list[tuple[int, str]],
                     ptr: int) -> tuple[int, int, float]:
    """
    Sliding-window search over 1..MAX_WIN consecutive verses starting at ptr.
    Returns (start_idx, end_idx_excl, best_score).
    """
    best_score = 0.0
    best_start = ptr
    best_end   = ptr + 1

    for start in range(ptr, min(ptr + 12, len(verses))):
        window_text = ""
        for end in range(start + 1, min(start + MAX_WIN + 1, len(verses) + 1)):
            window_text += (" " if window_text else "") + verses[end - 1][1]
            s = sim(hyp, window_text)
            if s > best_score:
                best_score = s
                best_start = start
                best_end   = end

    return best_start, best_end, best_score


def process_file(m4a_path: Path, surah_num: int,
                 verses: list[tuple[int, str]],
                 out_surah_dir: Path, manifest_fh) -> int:
    video_id = m4a_path.stem
    try:
        audio = decode_m4a(str(m4a_path))
    except Exception as e:
        print(f"    decode error {m4a_path.name}: {e}", flush=True)
        return 0

    chunk_len  = SR * CHUNK_S
    n_chunks   = (len(audio) + chunk_len - 1) // chunk_len
    saved      = 0
    ptr        = 0           # index into verses list
    miss_run   = 0           # consecutive misses

    for ci in range(n_chunks):
        if ptr >= len(verses):
            break
        seg = audio[ci * chunk_len:(ci + 1) * chunk_len]
        if len(seg) < SR * 2.0:   # skip very short trailing chunk
            break

        try:
            hyp = transcribe(seg)
        except Exception:
            hyp = ""

        if not hyp:
            miss_run += 1
            if miss_run >= LOOKAHEAD:
                ptr = min(ptr + 1, len(verses))
                miss_run = 0
            continue

        v_start, v_end, score = find_best_window(hyp, verses, ptr)

        if score < MATCH_THRESHOLD:
            miss_run += 1
            if miss_run >= LOOKAHEAD:
                ptr = min(ptr + 1, len(verses))
                miss_run = 0
            continue

        miss_run = 0

        # Canonical text = concatenation of matched verses
        canonical_text = " ".join(verses[vi][1] for vi in range(v_start, v_end))
        keys = " ".join(f"{surah_num}:{verses[vi][0]}" for vi in range(v_start, v_end))

        seg_aug = maybe_augment(seg)

        fname    = f"{video_id}_{ci:04d}.wav"
        wav_path = out_surah_dir / fname
        sf.write(str(wav_path), seg_aug, SR)
        rel = wav_path.relative_to(ROOT).as_posix()
        entry = {"key": keys, "text": canonical_text, "wav": rel}
        manifest_fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
        saved += 1

        ptr = v_end   # advance past matched verses

    return saved


# ── Main ──────────────────────────────────────────────────────────────────────

def load_resume_state() -> set[int]:
    """
    Lit le manifest existant et renvoie l'ensemble des sourates DEJA terminees.
    La sourate la plus haute presente est consideree partielle (interrompue) et
    sera re-traitee. Le manifest est reecrit en ne gardant que les sourates
    confirmees-terminees (lignes JSON valides uniquement).
    """
    if not ALIGN_MAN.exists():
        return set()

    valid_lines: list[str] = []
    surahs_present: set[int] = set()
    for line in open(ALIGN_MAN, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line.strip():
            continue
        try:
            obj = json.loads(line)
            s = int(obj["key"].split(" ")[0].split(":")[0])
            valid_lines.append((s, line))
            surahs_present.add(s)
        except Exception:
            continue   # ligne corrompue (ecriture interrompue)

    if not surahs_present:
        return set()

    # La sourate max est potentiellement partielle -> on la re-traite
    partial = max(surahs_present)
    done = surahs_present - {partial}

    # Reecrit le manifest en gardant uniquement les sourates confirmees
    with open(ALIGN_MAN, "w", encoding="utf-8") as f:
        for s, line in valid_lines:
            if s in done:
                f.write(line + "\n")

    print(f"[RESUME] Sourates terminees: {sorted(done)}", flush=True)
    print(f"[RESUME] Reprise a partir de la sourate {partial}", flush=True)
    return done


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print("Chargement base versets...", flush=True)
    verse_db = load_verse_db()

    done_surahs = load_resume_state()

    surah_dirs = sorted(YT_DIR.iterdir())
    total_files = sum(
        len(list(d.glob("*.m4a")) + list(d.glob("*.opus")) + list(d.glob("*.webm")))
        for d in surah_dirs if d.is_dir()
    )
    aug_label = f"bruit ACTIVE prob={NOISE_PROB}" if _aug_available else "bruit OFF"
    print(f"{len(surah_dirs)} sourates, {total_files} fichiers - {aug_label}", flush=True)

    total_saved = 0
    t0 = time.time()

    # Mode append : on conserve les sourates deja terminees
    with open(ALIGN_MAN, "a", encoding="utf-8") as mf:
        for surah_dir in sorted(YT_DIR.iterdir()):
            if not surah_dir.is_dir():
                continue
            m = re.match(r's(\d+)_', surah_dir.name)
            if not m:
                continue
            surah_num = int(m.group(1))
            if surah_num in done_surahs:
                print(f"  [{surah_num}] deja fait - skip", flush=True)
                continue
            verses    = verse_db.get(surah_num, [])
            if not verses:
                print(f"  [{surah_num}] aucun verset - skip", flush=True)
                continue

            out_surah = OUT_DIR / surah_dir.name
            out_surah.mkdir(exist_ok=True)

            audio_files = (list(surah_dir.glob("*.m4a"))
                           + list(surah_dir.glob("*.opus"))
                           + list(surah_dir.glob("*.webm")))

            saved_surah = 0
            for af in sorted(audio_files):
                n = process_file(af, surah_num, verses, out_surah, mf)
                saved_surah += n
                print(f"  [{surah_num:3d}] {af.name} -> {n} blocs alignes", flush=True)
            mf.flush()
            total_saved += saved_surah
            print(f"  Sourate {surah_num}: {saved_surah} blocs alignes / {len(verses)} versets",
                  flush=True)

    elapsed = time.time() - t0
    print(f"\nAlignement termine en {elapsed/60:.1f} min", flush=True)
    print(f"Total blocs alignes : {total_saved}", flush=True)

    # Merge avec train_full.jsonl
    print("\nConstruction train_combined.jsonl...", flush=True)
    orig_lines = open(TRAIN_ORIG, encoding="utf-8").readlines()
    yt_lines   = open(ALIGN_MAN,  encoding="utf-8").readlines()

    with open(TRAIN_COMB, "w", encoding="utf-8") as out:
        out.writelines(orig_lines)
        out.writelines(yt_lines)

    print(f"  Clips originaux  : {len(orig_lines):,}", flush=True)
    print(f"  Clips YouTube    : {len(yt_lines):,}", flush=True)
    print(f"  Total combine    : {len(orig_lines)+len(yt_lines):,}", flush=True)
    print(f"Sauvegarde -> {TRAIN_COMB}", flush=True)
    print("YOUTUBE ALIGN DONE", flush=True)


if __name__ == "__main__":
    main()
