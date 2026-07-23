#!/usr/bin/env python3
"""
QA TTS : Vérifie la qualité des fichiers audio générés.
Exclut les fichiers cassés, silencieux, ou mal générés.
"""
import json
from pathlib import Path
import numpy as np

try:
    import soundfile as sf
except ImportError:
    print("⚠️  soundfile manquant. Installer: pip install soundfile")
    exit(1)

BASE_DIR = Path(__file__).parent
WAV_DIR = BASE_DIR / "data" / "tts_augmentation" / "wav"
MANIFEST = BASE_DIR / "data" / "tts_augmentation" / "manifest.jsonl"

# Critères QA
MIN_DURATION = 0.5  # au moins 0.5s
MAX_DURATION = 30   # max 30s
MIN_RMS = 0.01      # amplitude minimale (pas silencieux)
MAX_CLIPPING = 0.95 # détection d'écrêtage

def analyze_wav(wav_path):
    """Retourne (is_valid, reason, metrics)"""
    try:
        audio, sr = sf.read(wav_path)
        duration = len(audio) / sr

        # Vérifications basiques
        if duration < MIN_DURATION:
            return False, "TOO_SHORT", {"duration": duration}
        if duration > MAX_DURATION:
            return False, "TOO_LONG", {"duration": duration}

        # RMS (énergie moyenne)
        rms = np.sqrt(np.mean(audio ** 2))
        if rms < MIN_RMS:
            return False, "SILENT", {"rms": float(rms)}

        # Détection d'écrêtage (saturation)
        peak = np.max(np.abs(audio))
        if peak > MAX_CLIPPING:
            return False, "CLIPPED", {"peak": float(peak)}

        # Vérif : pas d'audio vide
        if np.all(audio == 0):
            return False, "EMPTY", {}

        return True, "OK", {
            "duration": round(duration, 3),
            "rms": round(float(rms), 4),
            "peak": round(float(peak), 4),
        }

    except Exception as e:
        return False, f"ERROR: {str(e)[:50]}", {}

def main():
    print("🔍 Analyse qualité TTS...\n")

    # Charge manifest
    clips = []
    with open(MANIFEST) as f:
        for line in f:
            clips.append(json.loads(line))

    print(f"📊 Vérification {len(clips)} clips...\n")

    good = []
    bad = []
    bad_by_reason = {}

    for i, clip in enumerate(clips):
        wav_file = WAV_DIR / clip['clip']

        if not wav_file.exists():
            bad.append(clip)
            bad_by_reason.setdefault("MISSING", []).append(clip['clip'])
            continue

        is_valid, reason, metrics = analyze_wav(wav_file)

        if is_valid:
            good.append(clip)
        else:
            bad.append(clip)
            bad_by_reason.setdefault(reason, []).append(clip['clip'])

        if (i + 1) % 2000 == 0:
            print(f"  {i+1}/{len(clips)} — {len(good)} OK, {len(bad)} KO")

    print(f"\n📈 Résultats :")
    print(f"  ✅ Valides  : {len(good):5} / {len(clips)} ({100*len(good)/len(clips):.1f}%)")
    print(f"  ❌ Invalides: {len(bad):5} / {len(clips)} ({100*len(bad)/len(clips):.1f}%)")

    print(f"\n❌ Raisons de rejet :")
    for reason, files in sorted(bad_by_reason.items()):
        print(f"  {reason:20} : {len(files):5} fichiers")

    # Sauvegarde résultats
    manifest_good = BASE_DIR / "data" / "tts_augmentation" / "manifest_qa_clean.jsonl"
    with open(manifest_good, 'w', encoding='utf-8') as f:
        for clip in good:
            f.write(json.dumps(clip, ensure_ascii=False) + '\n')

    print(f"\n✅ Manifest nettoyé : {manifest_good}")
    print(f"   {len(good)} clips valides")

    # Sauvegarde liste rejetés (pour debug)
    rejected_list = BASE_DIR / "data" / "tts_augmentation" / "rejected_clips.txt"
    with open(rejected_list, 'w') as f:
        for clip in bad:
            f.write(f"{clip['clip']} — {clip.get('text', 'N/A')}\n")

    print(f"\n📋 Rejetés : {rejected_list} ({len(bad)} clips)")

if __name__ == "__main__":
    main()
