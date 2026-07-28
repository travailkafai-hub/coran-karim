#!/usr/bin/env bash
# Installe l'APK construit ICI sur les telephones branches sur le PC B.
#
# PIEGE PAYE (2026-07-28) : un chemin ABSOLU Windows ne survit pas aux
# echappements successifs bash -> ssh -> cmd. `adb install C:\Temp\x.apk`
# repondait « No such file or directory » ALORS QUE `dir` trouvait le fichier --
# et le script, qui avalait la sortie, laissait croire a une installation
# reussie. Consequence : trois recettes analysees sur un binaire vieux d'une
# heure, avec un `build=` du log qui ne correspondait pas a la source.
# On transfere donc dans le repertoire personnel et on installe par chemin
# RELATIF, puis on VERIFIE que « Success » apparait.
set -uo pipefail
PCB="${PCB:-kafai@100.126.49.93}"
ADB='C:\Users\kafai\platform-tools\adb.exe'
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=no -o LogLevel=ERROR)
APK="${1:-app/build/app/outputs/flutter-apk/app-debug.apk}"
[ -f "$APK" ] || { echo "APK introuvable : $APK" >&2; exit 1; }

echo "transfert de l'APK ($(du -h "$APK" | cut -f1))…"
scp "${SSH_OPTS[@]}" -q "$APK" "$PCB:neuf.apk" || { echo "transfert ECHOUE" >&2; exit 1; }

rc=0
for S in ${SERIALS:-R3CY20XW7TD m7geugpr8x5tfec6}; do
  printf "%-18s " "$S"
  out=$(ssh "${SSH_OPTS[@]}" "$PCB" "$ADB -s $S install -r neuf.apk" 2>&1 | tr -d '\r' | tail -1)
  echo "$out"
  case "$out" in *Success*) ;; *) rc=1 ;; esac
done
exit $rc
