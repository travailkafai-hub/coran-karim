#!/bin/bash
# Relancer la génération TTS pour les 52 clips manquants (tts_18115 à tts_18166)
# Manifest nettoyé : 18115 entrées valides (tts_0 à tts_18114)

set -e

cd "$(dirname "$0")"
BASE_DIR="$PWD"

echo "📊 État de la génération TTS :"
echo "  ✅ Fichiers générés : tts_0.wav à tts_18114.wav (18 115 clips)"
echo "  ❌ Manquent : tts_18115.wav à tts_18166.wav (52 clips)"
echo "  ✅ Manifest nettoyé : 18 115 entrées valides"
echo ""

echo "Relançant la génération TTS avec XTTS-v2..."
echo "(cela peut prendre quelques heures pour 52 clips)"
echo ""

# Relance avec Python système (venv TTS cassée après coupure courant)
export PYTHONPATH="$BASE_DIR/.venv_tts/lib/python3.14/site-packages:$PYTHONPATH"
export TTS_HOME="$BASE_DIR/tts-cache"
export HF_HOME="$BASE_DIR/hf-cache"
/usr/bin/python3.14 "$BASE_DIR/generate_tts_augmentation.py" --n-words 9500

echo ""
echo "✅ Génération TTS terminée !"
echo "Manifest final : $(wc -l < "$BASE_DIR/data/tts_augmentation/manifest.jsonl") entrées"
echo "Fichiers audio : $(ls "$BASE_DIR/data/tts_augmentation/wav/"tts_*.wav 2>/dev/null | wc -l) fichiers"
