"""
Convertit un manifest JSONL -> manifests NeMo (train/val).
Format NeMo : {"audio_filepath": "...", "duration": float, "text": "..."}
- Filtre les WAV manquants
- Normalise le texte (garde harakat, supprime marques Quraniques visuelles)
- Split 95/5 train/val

Usage:
    python prepare_nemo_data.py
    python prepare_nemo_data.py --manifest data/manifest_unified.jsonl
"""
import json, re, random, argparse
from pathlib import Path
import soundfile as sf
from tqdm import tqdm

BASE_DIR = Path(__file__).parent
DATA_DIR = BASE_DIR / "data"
OUT_DIR  = BASE_DIR / "nemo_manifests"
OUT_DIR.mkdir(exist_ok=True)

INPUT_JSONL = DATA_DIR / "manifest_full_wav.jsonl"


def normalize_text(text: str) -> str:
    # Caracteres absents du vocabulaire BPE (1024 tokens) du modele FastConformer
    # pcd -> le modele ne peut JAMAIS les predire (tombe en <unk>), meme apres
    # un entrainement infini. Verifie empiriquement contre vocab_pieces.json.
    text = text.replace("ٱ", "ا")  # alef wasla (elision de "ال") -> alef normal
    text = text.replace("ٰ", "ا")  # alef suscrit/dagger alif (voyelle longue) -> alef normal
    text = text.replace("ۥ", "و")  # petit waw (marque de lecture, fin de mot) -> waw normal
    text = text.replace("ۦ", "ي")  # petit yeh (marque de lecture, fin de mot) -> yeh normal
    text = text.replace("ٔ", "ء")  # hamza suscrite combinante -> hamza normale
    text = text.replace("ٓ", "")    # maddah combinante -> supprimee (deja portee par la lettre de base)
    text = text.replace("ـ", "")    # tatweel (allongement visuel, aucun son)
    text = text.replace("۞", "")    # marque de rub el hizb (repere de section, aucun son)
    text = text.replace("۩", "")    # marque de sajda (aucun son)
    text = re.sub(r"[ؖ-ؚۖ-ۜ۟-۪ۤۧۨ-ۭ]", "", text)
    text = re.sub(r"[،؛؟\.,!?:;\-_()\[\]{}\"\'»«]", "", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def get_duration(wav_path: Path) -> float:
    try:
        info = sf.info(str(wav_path))
        return info.frames / info.samplerate
    except Exception:
        return -1.0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", default=None,
                        help="Chemin du manifest JSONL (defaut: manifest_full_wav.jsonl)")
    args = parser.parse_args()

    input_jsonl = Path(args.manifest) if args.manifest else INPUT_JSONL
    print(f"Lecture de {input_jsonl}...")
    entries = []
    skipped = 0

    with open(input_jsonl, encoding="utf-8") as f:
        lines = f.readlines()

    print(f"  {len(lines)} lignes trouvees. Filtrage...")

    for line in tqdm(lines):
        entry = json.loads(line)
        wav_rel = entry.get("wav", "")
        if not wav_rel:
            skipped += 1
            continue

        wav_abs = BASE_DIR / wav_rel
        if not wav_abs.exists():
            skipped += 1
            continue

        text = normalize_text(entry.get("text", ""))
        if len(text.strip()) < 3:
            skipped += 1
            continue

        duration = entry.get("duration", -1.0)
        if duration <= 0:
            duration = get_duration(wav_abs)
        if duration < 0.5 or duration > 60.0:
            skipped += 1
            continue

        entries.append({
            "audio_filepath": str(wav_abs).replace("\\", "/"),
            "duration": round(duration, 3),
            "text": text,
        })

    print(f"  Conserves : {len(entries)} | Ignores : {skipped}")

    random.seed(42)
    random.shuffle(entries)
    split = int(len(entries) * 0.95)
    train = entries[:split]
    val   = entries[split:]

    train_path = OUT_DIR / "train_manifest.jsonl"
    val_path   = OUT_DIR / "val_manifest.jsonl"

    with open(train_path, "w", encoding="utf-8") as f:
        for e in train:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")

    with open(val_path, "w", encoding="utf-8") as f:
        for e in val:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")

    print(f"\nManifests ecrits :")
    print(f"  Train : {len(train)} clips -> {train_path}")
    print(f"  Val   : {len(val)} clips   -> {val_path}")

    durations = [e["duration"] for e in train]
    total_h = sum(durations) / 3600
    print(f"\n  Duree totale train : {total_h:.1f}h")
    print(f"  Duree moyenne      : {sum(durations)/len(durations):.1f}s")
    print(f"  Duree max          : {max(durations):.1f}s")


if __name__ == "__main__":
    main()
