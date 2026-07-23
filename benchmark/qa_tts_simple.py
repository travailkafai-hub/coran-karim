#!/usr/bin/env python3
"""
QA TTS simple : Vérifie taille et existence des fichiers.
Exclus les fichiers cassés, trop petits, ou manquants.
"""
import json
from pathlib import Path
import os

BASE_DIR = Path(__file__).parent
WAV_DIR = BASE_DIR / "data" / "tts_augmentation" / "wav"
MANIFEST = BASE_DIR / "data" / "tts_augmentation" / "manifest.jsonl"

# Fichiers WAV valides font généralement 50-200 KB
MIN_SIZE = 40000  # 40 KB min
MAX_SIZE = 500000  # 500 KB max (pour détecter corruption)

def main():
    print("🔍 Analyse QA TTS (fichiers) ...\n")

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

        size = os.path.getsize(wav_file)

        if size < MIN_SIZE:
            bad.append(clip)
            bad_by_reason.setdefault("TOO_SMALL", []).append((clip['clip'], size))
        elif size > MAX_SIZE:
            bad.append(clip)
            bad_by_reason.setdefault("TOO_LARGE", []).append((clip['clip'], size))
        else:
            good.append(clip)

        if (i + 1) % 5000 == 0:
            print(f"  {i+1}/{len(clips)} — {len(good)} OK, {len(bad)} KO")

    print(f"\n📈 Résultats :")
    print(f"  ✅ Valides  : {len(good):5} / {len(clips)} ({100*len(good)/len(clips):.1f}%)")
    print(f"  ❌ Invalides: {len(bad):5} / {len(clips)} ({100*len(bad)/len(clips):.1f}%)")

    print(f"\n❌ Raisons de rejet :")
    for reason in sorted(bad_by_reason.keys()):
        count = len(bad_by_reason[reason])
        print(f"  {reason:20} : {count:5} fichiers")
        if count <= 5:
            for item in bad_by_reason[reason][:5]:
                if isinstance(item, tuple):
                    print(f"    - {item[0]} ({item[1]} bytes)")
                else:
                    print(f"    - {item}")

    # Sauvegarde manifest propre
    manifest_clean = BASE_DIR / "data" / "tts_augmentation" / "manifest_qa_clean.jsonl"
    with open(manifest_clean, 'w', encoding='utf-8') as f:
        for clip in good:
            f.write(json.dumps(clip, ensure_ascii=False) + '\n')

    print(f"\n✅ Manifest nettoyé : manifest_qa_clean.jsonl")
    print(f"   {len(good)} / {len(clips)} clips valides")

if __name__ == "__main__":
    main()
