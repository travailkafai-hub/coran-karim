#!/usr/bin/env bash
# Eteint le PC quand l'entrainement Nemotron est termine (demande utilisateur
# 2026-07-26). Ne s'appuie PAS sur sudo (qui exige un mot de passe ici) mais sur
# `systemctl poweroff`, autorise sans authentification pour la session locale
# active -- verifie avant ecriture avec :
#     pkcheck --action-id org.freedesktop.login1.power-off --process $$
#
# GARDE-FOUS, dans cet ordre :
#  1. n'eteint QUE sur une fin PROPRE (marqueur "termine (code 0)" ecrit par
#     supervise_nemotron_ctc.sh apres que finetune_nemotron_ctc.py a rendu 0,
#     donc APRES l'ecriture de nemotron-ctc-final.nemo) ;
#  2. verifie que le .nemo final existe REELLEMENT avant d'eteindre -- une fin
#     "propre" sans modele sauvegarde serait un bug, pas une raison d'eteindre ;
#  3. delai d'annulation (GRACE, defaut 300 s) pendant lequel il suffit de creer
#     le fichier ANNULER pour tout arreter ;
#  4. si l'entrainement CRASHE et que le superviseur abandonne (process mort
#     sans marqueur de fin), on n'eteint PAS -- on laisse la machine allumee
#     pour pouvoir diagnostiquer.
#
# Annulation a tout moment :
#     touch "<dossier du run>/NE_PAS_ETEINDRE"
#   ou simplement tuer ce script.
set -uo pipefail

OUT="${1:-$(dirname "$0")/models/nemotron-ctc-v1}"
GRACE="${2:-300}"
LOG="$OUT/supervised.log"
FINAL="$OUT/nemotron-ctc-final.nemo"
ANNULER="$OUT/NE_PAS_ETEINDRE"
TRACE="$OUT/shutdown_watcher.log"

echo "$(date '+%F %T') veilleur demarre (grace=${GRACE}s, annuler avec : touch $ANNULER)" >> "$TRACE"

while true; do
    if [ -f "$ANNULER" ]; then
        echo "$(date '+%F %T') ANNULE par $ANNULER -- aucune extinction" >> "$TRACE"
        exit 0
    fi
    if grep -q "termine (code 0)" "$LOG" 2>/dev/null; then
        break
    fi
    # Le superviseur n'est plus la ET aucune fin propre : crash abandonne.
    # On laisse la machine allumee pour le diagnostic.
    if ! pgrep -f "supervise_nemotron_ctc.sh" >/dev/null 2>&1; then
        echo "$(date '+%F %T') superviseur absent SANS fin propre -- machine laissee allumee" >> "$TRACE"
        exit 1
    fi
    sleep 60
done

if [ ! -f "$FINAL" ]; then
    echo "$(date '+%F %T') fin propre MAIS $FINAL absent -- anomalie, pas d'extinction" >> "$TRACE"
    exit 1
fi

echo "$(date '+%F %T') entrainement termine, modele present -- extinction dans ${GRACE}s" >> "$TRACE"
# Resume des validations dans la trace, pour retrouver le resultat au reveil.
CSV=$(ls -t "$OUT"/logs/version_*/metrics.csv 2>/dev/null | head -1)
[ -n "$CSV" ] && awk -F, '$8!="" && $1 ~ /^[0-9]+$/ {last=$0} END{print "  derniere validation : "last}' "$CSV" >> "$TRACE"

for ((i=GRACE; i>0; i-=10)); do
    if [ -f "$ANNULER" ]; then
        echo "$(date '+%F %T') ANNULE pendant le delai de grace" >> "$TRACE"
        exit 0
    fi
    sleep 10
done

echo "$(date '+%F %T') EXTINCTION" >> "$TRACE"
systemctl poweroff
