#!/usr/bin/env bash
# Trace l'etat MATERIEL du telephone juge pendant une recette, une ligne/seconde.
#
# POURQUOI CE SCRIPT EXISTE (2026-07-29). Sur 9 passes de balayage, 4 ont
# decroche : l'ancre enjambe un bloc contigu de ~56 mots (toujours autour de
# 124-180), ou la session s'arrete net au mot 127. Le flux micro BRUT montre
# que le son etait pourtant present et fort sur toute la plage -- ce n'est donc
# ni la captation ni la recitation. Le phenomene est BINAIRE (4-6 % ou 30 %,
# jamais entre les deux) et INDIFFERENT A LA VERSION du code : il a frappe v2,
# v3 et v4 indistinctement, ce qui rend tout classement de versions impossible.
#
# Un `dumpsys thermalservice` lance a la main pendant la serie a donne
# « Thermal Status: 3 » = THROTTLING_SEVERE, avec la batterie passee de 40,6 a
# 45,3 degres en une heure de banc. Un etat binaire, qui ne regarde pas quel
# binaire tourne, et qui bride les frequences CPU : candidat direct pour un ASR
# qui n'arrive plus a suivre le flux. Restait a le PROUVER en le datant, d'ou
# cette trace.
#
#   ./benchmark/tracer_etat_telephone.sh <serial> <fichier_sortie> [periode_s]
#
# Sortie : TSV avec entete, une ligne par echantillon.
#   epoch_ms  iso  thermal_status  ap  skin  bat  batterie_pct
#
# Se termine sur SIGTERM/SIGINT (le banc le tue a la fin de la recette).
set -uo pipefail
S="${1:?serial attendu}"; OUT="${2:?fichier de sortie attendu}"; PER="${3:-5}"
PKG=com.corankarim.coran_karim

printf 'epoch_ms\tiso\tthermal_status\tap\tskin\tbat\tbatterie_pct\n' > "$OUT"

# Un seul appel adb par echantillon : `dumpsys thermalservice` coute deja ~100 ms,
# en enchainer quatre par seconde perturberait la mesure qu'on cherche a faire.
# On agrege donc cote telephone et on ne ramene qu'une ligne. Periode 5 s :
# mesure faite, le cache thermique d'Android ne se rafraichit pas plus vite
# (six echantillons a 1 s ont rendu six fois la meme valeur au centieme).
while :; do
  # PIEGE PAYE (2026-07-29, une trace de 5 min jetee) : `dumpsys thermalservice`
  # publie DEUX jeux de valeurs -- « Cached temperatures » puis « Current
  # temperatures from HAL ». Le cache est FIGE : soixante echantillons ont rendu
  # 55.7/45.4/36.0 a la decimale pres pendant que l'ASR tournait, et l'ecart avec
  # le HAL au meme instant atteignait 4 degres sur la batterie. Une sonde qui ne
  # varie jamais ne mesure pas, elle repete -- et elle aurait « prouve » que la
  # temperature ne joue aucun role. On ne lit donc QUE la section HAL, en
  # amorcant sur son titre.
  L=$(adb -s "$S" shell "
    T=\$(dumpsys thermalservice 2>/dev/null)
    ST=\$(echo \"\$T\" | sed -n 's/^Thermal Status: //p' | head -1)
    H=\$(echo \"\$T\" | sed -n '/Current temperatures from HAL/,/^[A-Z]/p')
    AP=\$(echo \"\$H\" | sed -n 's/.*mValue=\([0-9.]*\).*mName=AP,.*/\1/p' | head -1)
    SK=\$(echo \"\$H\" | sed -n 's/.*mValue=\([0-9.]*\).*mName=SKIN,.*/\1/p' | head -1)
    BT=\$(echo \"\$H\" | sed -n 's/.*mValue=\([0-9.]*\).*mName=BAT,.*/\1/p' | head -1)
    PC=\$(dumpsys battery 2>/dev/null | sed -n 's/^  level: //p' | head -1)
    echo \"\$ST|\$AP|\$SK|\$BT|\$PC\"
  " 2>/dev/null | tr -d '\r' | tail -1)

  IFS='|' read -r ST AP SK BT PC <<< "$L"
  # %3N n'est pas interprete par le `date` de ce poste (il sort des
  # nanosecondes) : on tronque explicitement plutot que de propager un
  # horodatage faux de six ordres de grandeur, qui rendrait tout recoupement
  # avec le log de session silencieusement absurde.
  MS=$(( $(date +%s) * 1000 + 10#$(date +%N) / 1000000 ))
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$MS" "$(date +%H:%M:%S)" "${ST:-?}" "${AP:-?}" "${SK:-?}" "${BT:-?}" "${PC:-?}" >> "$OUT"
  sleep "$PER"
done
