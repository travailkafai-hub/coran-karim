#!/usr/bin/env bash
# Installe l'APK construit ICI sur les telephones branches sur le PC B.
# L'APK doit d'abord traverser : `adb install` s'execute la-bas et ne voit que
# le disque de la-bas.
set -uo pipefail
PCB="${PCB:-kafai@100.126.49.93}"
ADB='C:\Users\kafai\platform-tools\adb.exe'
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=no -o LogLevel=ERROR)
APK="${1:-app/build/app/outputs/flutter-apk/app-debug.apk}"
[ -f "$APK" ] || { echo "APK introuvable : $APK" >&2; exit 1; }
DIST='C:\Temp\coran-karim.apk'
ssh "${SSH_OPTS[@]}" "$PCB" 'mkdir C:\Temp 2>nul & exit 0' >/dev/null 2>&1
echo "transfert de l'APK ($(du -h "$APK" | cut -f1))…"
scp "${SSH_OPTS[@]}" -q "$APK" "$PCB:C:/Temp/coran-karim.apk" || exit 1
for S in "${@:2}"; do :; done
for S in ${SERIALS:-R3CY20XW7TD m7geugpr8x5tfec6}; do
  printf "%-18s " "$S"
  ssh "${SSH_OPTS[@]}" "$PCB" "$ADB -s $S install -r \"$DIST\"" 2>/dev/null | tr -d '\r' | tail -1
done
