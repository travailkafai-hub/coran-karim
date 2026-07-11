"""
Convertit l'Arabic Speech Corpus (Nawar Halabi) en NeMo manifest JSONL.
Conserve les harakat (tashkeel) — c'est l'objectif de ce corpus dans le dataset
augmenté : ancrer le modèle sur la phonétique réelle plutôt que sur la mémoire
du texte coranique canonique.

Format source (confirmé par inspection du zip) :
  arabic_speech_corpus/wav/ARA NORM  NNNN.wav   (48 kHz mono, NB: double espace dans le nom)
  arabic_speech_corpus/orthographic-transcript.txt
    une ligne par clip : "ARA NORM  NNNN.wav" "texte en Buckwalter"
    - transcription en Buckwalter STANDARD sauf ^ utilisé pour ث (au lieu de v)
    - '-' marque une pause (silence), pas un phonème -> supprimé
    - 1813 lignes = 1813 wav (le "test set" à 100 clips n'a pas de transcript
      séparé au niveau racine et n'est pas utilisé ici)

Prérequis : python download_arabic_speech_corpus.py déjà exécuté.

Usage:
    "D:/Coran Karim/benchmark/.venv/Scripts/python.exe" -X utf8 prepare_arabic_speech_corpus_manifest.py
Sortie:
    benchmark/arabic_speech_corpus/asc_manifest.jsonl  ← utilisé par prepare_augmented_manifest.py
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import json, re
from pathlib import Path
import soundfile as sf
import numpy as np
from tqdm import tqdm

BASE_DIR    = Path(__file__).parent
ASC_DIR     = BASE_DIR / "arabic_speech_corpus"
WAV_DIR     = ASC_DIR / "wav"
WAV16_DIR   = ASC_DIR / "wav16k"
TRANSCRIPT  = ASC_DIR / "orthographic-transcript.txt"
OUT_JSONL   = ASC_DIR / "asc_manifest.jsonl"

TARGET_SR   = 16000
MIN_DUR     = 0.5
MAX_DUR     = 30.0

LINE_RE = re.compile(r'^"([^"]+)"\s+"([^"]*)"\s*$')


# ─── Table de translittération Buckwalter → arabe ────────────────────────────
# Variante utilisée par ce corpus précis : '^' représente ث (au lieu du 'v'
# standard) — vérifié empiriquement (ex: "Al^~aAniy" -> "الثّاني" = "le second",
# "ka^iyrapK" -> "كَثِيرَةٍ" = "nombreuse"). Les deux formes sont mappées par
# sécurité, au cas où une variante alternative du corpus utiliserait 'v'.
BUCKWALTER_TO_ARABIC = {
    "'": "ء", "|": "آ", ">": "أ", "&": "ؤ", "<": "إ", "}": "ئ",
    "A": "ا", "b": "ب", "p": "ة", "t": "ت", "^": "ث", "v": "ث",
    "j": "ج", "H": "ح", "x": "خ", "d": "د", "*": "ذ", "r": "ر",
    "z": "ز", "s": "س", "$": "ش", "S": "ص", "D": "ض", "T": "ط",
    "Z": "ظ", "E": "ع", "g": "غ", "f": "ف", "q": "ق", "k": "ك",
    "l": "ل", "m": "م", "n": "ن", "h": "ه", "w": "و", "y": "ي",
    "Y": "ى",
    # Diacritiques (harakat) — PRÉSERVÉS, c'est tout l'intérêt de ce corpus
    "F": "ً", "N": "ٌ", "K": "ٍ", "a": "َ", "u": "ُ", "i": "ِ",
    "~": "ّ", "o": "ْ", "`": "ٰ",
    # Marqueur de pause (silence) — pas un phonème, supprimé
    "-": "",
}


def buckwalter_to_arabic(text: str) -> str:
    out = []
    unknown = set()
    for ch in text:
        if ch in BUCKWALTER_TO_ARABIC:
            out.append(BUCKWALTER_TO_ARABIC[ch])
        elif ch == " ":
            out.append(" ")
        else:
            unknown.add(ch)
            out.append(ch)  # conserve tel quel, nettoyé ensuite par normalize_text
    if unknown:
        print(f"  [WARN] caractères Buckwalter non mappés : {unknown}")
    return "".join(out)


# ─── Normalisation finale (identique à prepare_nemo_data.py) ─────────────────
# Enlève uniquement ponctuation / marques visuelles hors-vocabulaire BPE.
# *** GARDE LES HARAKAT ***
def normalize_text(text: str) -> str:
    text = text.replace("ٱ", "ا")
    text = text.replace("ٰ", "ا")
    text = text.replace("ۥ", "و")
    text = text.replace("ۦ", "ي")
    text = text.replace("ٔ", "ء")
    text = text.replace("ٓ", "")
    text = text.replace("ـ", "")
    text = text.replace("۞", "")
    text = text.replace("۩", "")
    text = re.sub(r"[ؖ-ؚۖ-ۜ۟-۪ۤۧۨ-ۭ]", "", text)
    text = re.sub(r"[،؛؟\.,!?:;\-_()\[\]{}\"\'»«]", "", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def maybe_resample(wav_path: Path) -> tuple[Path, float]:
    """Ré-échantillonne à 16 kHz si nécessaire, retourne (chemin, durée)."""
    try:
        info = sf.info(str(wav_path))
    except Exception:
        return wav_path, -1.0

    duration = info.frames / info.samplerate
    if info.samplerate == TARGET_SR:
        return wav_path, duration

    WAV16_DIR.mkdir(parents=True, exist_ok=True)
    out_path = WAV16_DIR / wav_path.name
    if out_path.exists():
        info16 = sf.info(str(out_path))
        return out_path, info16.frames / info16.samplerate

    from scipy.signal import resample_poly
    from math import gcd
    audio, sr = sf.read(str(wav_path), always_2d=False)
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    g = gcd(TARGET_SR, sr)
    audio16 = resample_poly(audio, TARGET_SR // g, sr // g)
    sf.write(str(out_path), audio16.astype(np.float32), TARGET_SR, subtype="PCM_16")
    return out_path, len(audio16) / TARGET_SR


def main():
    if not TRANSCRIPT.exists():
        print(f"ERREUR: {TRANSCRIPT} introuvable. Lance d'abord download_arabic_speech_corpus.py")
        return

    lines = TRANSCRIPT.read_text(encoding="utf-8", errors="replace").splitlines()
    print(f"Lignes transcription : {len(lines)}")

    entries  = []
    skipped  = 0
    need_16k = 0

    for line in tqdm(lines, desc="ASC"):
        line = line.strip()
        if not line:
            continue
        m = LINE_RE.match(line)
        if not m:
            skipped += 1
            continue
        wav_name, buckwalter_text = m.group(1), m.group(2)

        wav_path = WAV_DIR / wav_name
        if not wav_path.exists():
            skipped += 1
            continue

        arabic_text = buckwalter_to_arabic(buckwalter_text)
        text = normalize_text(arabic_text)
        if len(text.strip()) < 3:
            skipped += 1
            continue

        actual_path, duration = maybe_resample(wav_path)
        if actual_path != wav_path:
            need_16k += 1

        if duration < MIN_DUR or duration > MAX_DUR:
            skipped += 1
            continue

        entries.append({
            "audio_filepath": str(actual_path).replace("\\", "/"),
            "duration": round(duration, 3),
            "text": text,
        })

    print(f"\nEntrées valides : {len(entries)} | ignorées : {skipped}")
    if need_16k > 0:
        print(f"Ré-échantillonnés à 16 kHz : {need_16k}")

    total_h = sum(e["duration"] for e in entries) / 3600
    print(f"Durée totale   : {total_h:.2f}h")

    with open(OUT_JSONL, "w", encoding="utf-8") as f:
        for e in entries:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")

    print(f"\nManifest écrit : {OUT_JSONL}")
    print("\nExemples :")
    for e in entries[:3]:
        print(f"  {e['text']}")
    print("\nÉtape suivante : python prepare_augmented_manifest.py")


if __name__ == "__main__":
    main()
