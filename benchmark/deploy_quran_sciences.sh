#!/bin/bash
# Redeploie les donnees de la cascade d'explication (tafsir offline) sur le
# telephone. A RELANCER apres chaque `flutter install`/reinstallation de l'app :
# desinstaller l'app efface son dossier files/ -> les donnees quran_sciences
# sont perdues et l'app retombe sur le repli Gemma ("aucune explication").
#
# Usage : bash deploy_quran_sciences.sh
export MSYS_NO_PATHCONV=1   # sinon Git Bash mutile les chemins /data/...
ADB="/c/Users/Adam/AppData/Local/Android/Sdk/platform-tools/adb.exe"
PKG="com.corankarim.coran_karim"
SRC="$(dirname "$0")/data/quran_sciences"
FILES="ayah_explanations.jsonl ayah_explanations.offsets.json word_explanations.jsonl word_explanations.offsets.json word_root_index.jsonl"

cd "$SRC" || { echo "dossier source introuvable: $SRC"; exit 1; }

echo "== push vers /data/local/tmp =="
for f in $FILES; do "$ADB" push "$f" "/data/local/tmp/qs_$f" 2>&1 | tail -1; done

echo "== copie dans le dossier prive de l'app (run-as) =="
"$ADB" shell run-as $PKG mkdir -p files/quran_sciences
for f in $FILES; do "$ADB" shell "run-as $PKG cp /data/local/tmp/qs_$f files/quran_sciences/$f"; done

echo "== nettoyage tmp =="
"$ADB" shell "rm -f /data/local/tmp/qs_*"

echo "== verification =="
"$ADB" shell run-as $PKG ls -la files/quran_sciences/

echo "== redemarrage app (pour recharger la cascade) =="
"$ADB" shell am force-stop $PKG
echo "OK -- rouvre l'app."
