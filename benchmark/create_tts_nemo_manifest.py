#!/usr/bin/env python3
"""
Crée manifest NeMo pour les clips TTS nettoyés.
Combine avec dataset d'entraînement existant.
"""
import json
from pathlib import Path
import soundfile as sf

BASE_DIR = Path(__file__).parent
TTS_MANIFEST = BASE_DIR / "data" / "tts_augmentation" / "manifest_qa_clean.jsonl"
TTS_WAV_DIR = BASE_DIR / "data" / "tts_augmentation" / "wav"
TRAIN_MANIFEST = BASE_DIR / "nemo_manifests" / "train_manifest.jsonl"
OUTPUT_MANIFEST = BASE_DIR / "nemo_manifests" / "train_manifest_augmented.jsonl"

def get_duration(wav_path):
    """Retourne durée en secondes"""
    try:
        audio, sr = sf.read(wav_path)
        return len(audio) / sr
    except:
        return 0

def main():
    print("📝 Création manifest NeMo augmenté...\n")

    # Charge clips TTS
    tts_clips = []
    try:
        with open(TTS_MANIFEST) as f:
            for line in f:
                tts_clips.append(json.loads(line))
    except ImportError:
        print("⚠️  soundfile manquant. Installant...")
        import subprocess
        subprocess.run(["python3", "-m", "pip", "install", "soundfile", "--quiet"])
        import soundfile as sf
        with open(TTS_MANIFEST) as f:
            for line in f:
                tts_clips.append(json.loads(line))

    print(f"📊 {len(tts_clips)} clips TTS à ajouter\n")

    # Convertit en format NeMo
    nemo_entries = []
    skipped = 0

    for clip in tts_clips:
        wav_path = TTS_WAV_DIR / clip['clip']

        if not wav_path.exists():
            skipped += 1
            continue

        # Duration
        try:
            duration = get_duration(wav_path)
            if duration < 0.5 or duration > 30:
                skipped += 1
                continue
        except:
            skipped += 1
            continue

        # Format NeMo
        nemo_entry = {
            "audio_filepath": str(wav_path.absolute()),
            "text": clip['text'],  # Texte avec l'erreur délibérée
            "duration": duration
        }
        nemo_entries.append(nemo_entry)

    print(f"✅ {len(nemo_entries)} entrées NeMo créées")
    print(f"⏭️  {skipped} clips skippés (durée/manquants)\n")

    # Charge manifest original
    original_count = 0
    with open(TRAIN_MANIFEST) as f:
        original_count = sum(1 for _ in f)

    print(f"📦 Manifest original: {original_count} clips")

    # Combine et sauvegarde
    print(f"🔗 Combinaison...")
    with open(OUTPUT_MANIFEST, 'w', encoding='utf-8') as f:
        # Original
        with open(TRAIN_MANIFEST) as orig:
            for line in orig:
                f.write(line)

        # TTS augmentation
        for entry in nemo_entries:
            f.write(json.dumps(entry, ensure_ascii=False) + '\n')

    final_count = original_count + len(nemo_entries)
    print(f"\n✅ Manifest augmenté sauvegardé!")
    print(f"   Original:   {original_count:6} clips")
    print(f"   + TTS:      {len(nemo_entries):6} clips")
    print(f"   = Total:    {final_count:6} clips")
    print(f"\n📁 {OUTPUT_MANIFEST}")

if __name__ == "__main__":
    main()
