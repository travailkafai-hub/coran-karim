#!/usr/bin/env bash
# Recette à deux téléphones — une commande, aucun tap.
#
# Le XIAOMI joue le récitateur, le SAMSUNG écoute et juge. Même sourate des deux
# côtés : c'est la seule façon d'avoir deux mesures comparables d'une itération
# à l'autre.
#
#   ./benchmark/recette_2tel.sh [sourate] [duree_s]
#
# En sortie : un dossier horodaté sous benchmark/recettes/ contenant le log
# isolé de la session, les WAV (flux brut + clips) et un resume.txt.
#
# POURQUOI CE SCRIPT EXISTE : chaque test demandait la même navigation manuelle
# sur deux appareils. Refait à la main, c'est du temps perdu et surtout un
# protocole qui varie entre deux mesures censées être comparables (décision
# utilisateur 2026-07-28).
set -uo pipefail

SAMSUNG="${SAMSUNG:-R3CY20XW7TD}"     # écoute et juge
XIAOMI="${XIAOMI:-m7geugpr8x5tfec6}"  # joue le récitateur
SOURATE="${1:-2}"                     # varier les passages : ajuster sur un seul
                                      # revient a corriger CE texte, pas la chaine
# WAV=<chemin local> : recette DETERMINISTE -- le fichier est pousse sur le juge
# et rejoue A LA PLACE du micro, donc le Xiaomi n'est pas utilise. Chaque passe
# devient identique au bit pres. Mesure qui l'impose : par haut-parleur -> micro,
# le MEME binaire sur la MEME sourate donne 1,4 % puis 4,3 % de mots non verts,
# et les passes vont de 0,0 % a 10,9 % -- la variance du banc depasse l'effet
# cherche, donc tout « gain » annonce serait du bruit.
WAV="${WAV:-}"
DUREE="${2:-75}"
PKG=com.corankarim.coran_karim
LOG=/sdcard/Android/data/$PKG/files/recitation_diagnostic.log
RACINE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$RACINE/benchmark/recettes/$(date +%Y%m%d-%H%M%S)-s$SOURATE"

mort() { echo "ARRET : $*" >&2; exit 1; }

for d in "$SAMSUNG" "$XIAOMI"; do
  adb devices | grep -q "^$d[[:space:]]*device$" || mort "appareil $d absent (adb devices)"
done
mkdir -p "$OUT"

# Repère de départ : le log est cumulatif, on note sa taille pour n'extraire
# QUE cette session à la fin (sinon on analyse la précédente sans le voir).
AVANT=$(adb -s "$SAMSUNG" shell "wc -l < $LOG" 2>/dev/null | tr -d '\r ' || echo 0)
echo "sourate=$SOURATE duree=${DUREE}s  log a $AVANT lignes"

adb -s "$SAMSUNG" shell am force-stop $PKG >/dev/null 2>&1
adb -s "$XIAOMI"  shell am force-stop $PKG >/dev/null 2>&1
sleep 2

# L'APK est DEBOGABLE a dessein : `run-as` -- donc la recuperation des WAV de
# session -- ne fonctionne que dans ce mode (verifie : « run-as: package not
# debuggable » sur un build release). Contrepartie : Android pose son
# avertissement de compatibilite par-dessus l'app. On l'ecarte plutot que de
# renoncer a l'audio, qui est le seul juge de paix entre « faute de recitation »
# et « defaut d'architecture ».
python3 "$RACINE/benchmark/ecarter_dialogue.py" "$SAMSUNG" "$XIAOMI" 2>/dev/null || true

# L'écoute démarre EN PREMIER : le micro doit tourner avant le premier mot,
# sinon le début de la sourate n'est jamais capté et l'ancre part déjà en retard.
EXTRA_WAV=""
if [ -n "$WAV" ]; then
  [ -f "$WAV" ] || mort "WAV introuvable : $WAV"
  DIST=/sdcard/recette_source.wav
  adb -s "$SAMSUNG" push "$WAV" "$DIST" >/dev/null || mort "push du WAV impossible"
  EXTRA_WAV="--es wav $DIST"
  echo "source deterministe : $(basename "$WAV")"
fi
adb -s "$SAMSUNG" shell am start -n $PKG/.MainActivity \
    --es recette ecoute --ei sourate "$SOURATE" $EXTRA_WAV >/dev/null
# Aucun tap ici : l'intent `ecoute` fait atterrir DANS la recitation deja
# demarree (cf. KaraokeRecitationScreen.autoDemarrer).
CENTRE=$(adb -s "$SAMSUNG" shell wm size | tr -d '\r' | sed 's/.*: //' | awk -Fx '{print int($1/2), int($2/2)}')

# ATTENTE ACTIVE, pas un sleep fixe (demande utilisateur 2026-07-28 : « il ne
# faut pas lancer l'audio tant que tu n'es pas dans la page de recitation »).
# Un delai en dur est faux dans les deux sens : trop court, le recitateur parle
# avant que le micro tourne et le debut n'est jamais capte ; trop long, on perd
# du temps a chaque iteration. On attend le marqueur que l'app ecrit elle-meme
# quand la capture est REELLEMENT ouverte.
python3 "$RACINE/benchmark/ecarter_dialogue.py" "$SAMSUNG" 2>/dev/null || true
echo -n "attente de l'ouverture du micro"
PRET=0
for _ in $(seq 1 40); do
  sleep 1; echo -n "."
  if adb -s "$SAMSUNG" shell "tail -n 60 $LOG" 2>/dev/null | grep -q "capture ouverte"; then
    PRET=1; break
  fi
done
echo
[ "$PRET" = 1 ] || mort "le micro ne s'est jamais ouvert cote juge -- rien a mesurer"
sleep 2
if [ -z "$WAV" ]; then
  adb -s "$XIAOMI" shell am start -n $PKG/.MainActivity \
      --es recette lecture --ei sourate "$SOURATE" >/dev/null
fi

echo "recitation en cours (${DUREE}s)…"
sleep "$DUREE"

# Second tap = arret de la session. C'est CE chemin qui vide la trace fine
# accumulee en memoire dans le fichier de log (cf. _flushTraces, appele par
# stop()/stopContinuous). Sans lui la trace est perdue a la fermeture, et on
# ne peut plus savoir ce qui a tenu la chaine pendant les trous.
adb -s "$SAMSUNG" shell input tap $CENTRE >/dev/null 2>&1
sleep 8
adb -s "$XIAOMI" shell am force-stop $PKG >/dev/null 2>&1
sleep 2

adb -s "$SAMSUNG" shell "cat $LOG" > "$OUT/full.log" 2>/dev/null
tail -n +"$((AVANT + 1))" "$OUT/full.log" > "$OUT/session.log"

SESS=$(adb -s "$SAMSUNG" shell "run-as $PKG ls -t app_flutter/recitation_captures/" 2>/dev/null | tr -d '\r' | head -1)
if [ -n "$SESS" ]; then
  adb -s "$SAMSUNG" shell "run-as $PKG tar cf - -C app_flutter/recitation_captures/$SESS ." > "$OUT/wav.tar" 2>/dev/null
  mkdir -p "$OUT/wav" && tar xf "$OUT/wav.tar" -C "$OUT/wav" 2>/dev/null && rm -f "$OUT/wav.tar"
fi

{
  echo "sourate=$SOURATE duree=${DUREE}s  $(date '+%F %T')"
  echo "lignes de session : $(wc -l < "$OUT/session.log")"
  grep '\[PARAMS\]' "$OUT/session.log" | sed 's/^[0-9T:.-]* //'
  echo "clips : $(ls "$OUT/wav"/clip_*.wav 2>/dev/null | wc -l)"
} > "$OUT/resume.txt"

cat "$OUT/resume.txt"
echo "-> $OUT"
