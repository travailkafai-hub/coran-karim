#!/usr/bin/env bash
# Rejoue TOUTES les versions sur le MEME audio, avec le MEME banc.
#
# POURQUOI CE PROTOCOLE. Les classements de versions du 2026-07-29 etaient faux :
# ils comparaient des passes MICRO, dont la dispersion a code IDENTIQUE va de
# 1,15 % a 5,63 % (v8 et v9 ont le meme aligneur, diff vide). Tout ecart plus
# petit que ca est du tirage, pas une difference de version.
#
# Ici : le VRAI test, celui qui compte -- le Redmi recite par son haut-parleur,
# le Samsung ecoute au micro et juge. Pas de rejeu de fichier : il court-circuite
# le micro, donc il ne mesure pas la chaine reelle (demande utilisateur).
#
# Comme le micro est bruite, on fait TROIS passes par version et on rapporte
# l'etendue, jamais une valeur seule. Un ecart inferieur a l'etendue ne conclut
# rien.
#
# ON NE FAIT VARIER QUE LA CHAINE DE RECITATION : on greffe les trois fichiers
# de chaine (buffer, aligneur, jugement) de chaque version sur le banc actuel,
# qui reste constant. Sans ca on comparerait aussi les changements de banc.
set -uo pipefail
cd "$(dirname "$0")/.."
SOURATE="${SOURATE:-2}"; DUREE="${DUREE:-420}"; PASSES="${PASSES:-3}"
SAMSUNG=R3CY20XW7TD; XIAOMI=m7geugpr8x5tfec6
# Pilote adb : distant par defaut (telephones sur le PC B), cf. adb_pcb.sh.
# Mettre ADBBIN=adb pour des appareils branches sur CE poste.
ADBBIN="${ADBBIN:-$(pwd)/benchmark/adb_pcb.sh}"
# PIEGE PAYE (2026-07-29) : recette_2tel.sh lit la variable ADB, PAS ADBBIN.
# Sans cet export, `ADBBIN=adb balayage_versions.sh` compilait et installait bien
# en LOCAL, puis chaque recette repartait sur le pilote PC B par defaut, mourait
# en 1 s sur « appareil absent » -- et comme sa sortie va dans /tmp/rec_$$.log,
# l'echec etait MUET : le balayage defilait v2 -> v3 -> v4 sans un seul chiffre.
export ADB="$ADBBIN"
CHAINE="app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt
app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/ForcedAligner.kt
app/lib/providers/recitation_provider.dart"
TAGF=app/lib/services/diagnostic_log.dart
VERSIONS="44305da:v2-voisins
a97867f:v3-troncature
8507b0e:v4-sans-palliatif
363a3a1:v8-contexte-droit
b72b05b:v9-deterministe
6ae0884:v10-dp-droite
f2d61bc:v11-coupe-stable
36c03d0:v13-rayon08
6d07754:v16-expansion
4606d64:v18-resync-texte
69de15a:v21-sans-expansion
305db63:v22-resync-mesure
41df3e3:v23-sans-resync"
export PATH="/media/kafai/NouveauNom/flutter/bin:$PATH"
echo "### balayage : $(echo "$VERSIONS" | wc -l) versions x $PASSES passes MICRO | sourate $SOURATE"
echo "### Redmi recite au haut-parleur, Samsung ecoute -- aucun rejeu de fichier"
for e in $VERSIONS; do
  C="${e%%:*}"; T="causal-${e##*:}"
  echo; echo "=== $T ($C) ==="
  git checkout HEAD -- $CHAINE $TAGF 2>/dev/null
  if ! git checkout "$C" -- $CHAINE 2>/dev/null; then
    echo "  IGNOREE : fichiers absents a ce commit"; continue
  fi
  sed -i "s/_kBuildTag = '[^']*'/_kBuildTag = '$T'/" $TAGF
  if ! (cd app && flutter build apk --debug >/tmp/build_$$.log 2>&1); then
    echo "  COMPILATION IMPOSSIBLE -- $(grep -m2 -i 'error' /tmp/build_$$.log | head -2 | cut -c1-110)"
    continue
  fi
  # Les DEUX telephones : le Redmi porte l'app qui recite, le Samsung celle qui juge.
  # En distant l'APK est sur CE disque : il faut le transferer d'abord, c'est
  # tout le role d'installer_pcb.sh (un `adb install` distant ne verrait pas le
  # fichier). Piege deja tombe : l'echec est SILENCIEUX, et trois recettes ont
  # ete analysees sur un binaire perime -- d'ou la verification de "Success".
  if [ "$ADBBIN" = "adb" ]; then
    for s in $SAMSUNG $XIAOMI; do
      adb -s $s install -r app/build/app/outputs/flutter-apk/app-debug.apk >/dev/null 2>&1 \
        || { echo "  INSTALL ECHOUE sur $s"; continue 2; }
    done
  else
    OK=$(bash benchmark/installer_pcb.sh 2>&1 | grep -c Success)
    [ "$OK" -ge 2 ] || { echo "  INSTALL ECHOUE ($OK/2 Success)"; continue; }
  fi
  for i in $(seq 1 $PASSES); do
    timeout 900 bash benchmark/recette_2tel.sh "$SOURATE" "$DUREE" >/tmp/rec_$$.log 2>&1
    D=$(grep -o '/media.*recettes/[0-9-]*-s[0-9]*' /tmp/rec_$$.log | tail -1)
    # Un echec de recette doit se VOIR. Muet, il se confond avec un banc qui
    # tourne -- c'est ce qui a fait perdre une heure le 2026-07-29.
    if [ -z "$D" ]; then
      echo "  PASSE $i ECHOUEE : $(grep -m1 'ARRET' /tmp/rec_$$.log || tail -1 /tmp/rec_$$.log)"
      continue
    fi
    python3 benchmark/taux_non_verts.py "$D/" 2>&1 | sed 's/^/  /'
  done
done
git checkout HEAD -- $CHAINE $TAGF 2>/dev/null
echo; echo "### termine, arbre restaure a HEAD"
