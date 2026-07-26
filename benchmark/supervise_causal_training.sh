#!/usr/bin/env bash
# Superviseur : relance automatiquement finetune_streaming_causal.py apres un
# crash (Xid 8 du driver GPU, survenu 2 fois en 1h le 2026-07-25 -- cf.
# references/asr.md du skill model-training, "Incident : crash GPU"). Le GPU
# redevient sain immediatement, seul le PROCESSUS meurt -- ce superviseur
# evite une intervention manuelle a chaque occurrence.
#
# Usage : ./supervise_causal_training.sh <dossier_sortie> [args... passes tels
#         quels a finetune_streaming_causal.py, ex. --lr 3e-4 --contexts 70,13]
# Le PREMIER lancement peut porter --init_weights_from <ckpt> pour un
# redemarrage a chaud (nouvel optimiseur/scheduler) ; les relances APRES un
# crash utilisent toujours --resume_from <dernier ckpt DE CE DOSSIER> pour
# continuer l'etat exact plutot que de repartir a chaud a chaque fois.
set -uo pipefail
cd "$(dirname "$0")"
SITE="$PWD/.venv_nemo/lib/python3.14/site-packages"
export PYTHONPATH="$SITE"
export CUDA_HOME="$SITE/nvidia/cuda_nvcc"

OUT="$1"; shift
mkdir -p "$OUT"
LOG="$OUT/supervised.log"
# BUG CORRIGE (2026-07-26) : les hyperparametres fixes (--epochs, --contexts,
# --lr, --save_top_k) doivent etre repasses a CHAQUE relance, pas seulement la
# premiere -- sinon une reprise apres crash retombe sur les defauts du script
# (`--epochs` par defaut = 4), et `trainer.fit` s'arrete en pensant avoir
# fini alors qu'il ne restait qu'a reprendre. Constate : run arrete a l'epoch
# 4/4 (code 0, "propre") alors que 20 epochs etaient demandees -- 16 epochs
# perdues sans le moindre message d'erreur.
# `--init_weights_from` est retire des args persistants : il ne sert QUE pour
# amorcer un tout premier redemarrage a chaud, jamais pour les reprises
# suivantes (qui utilisent --resume_from, etat complet).
PERSISTENT_ARGS=()
skip_next=0
for a in "$@"; do
    if [ "$skip_next" -eq 1 ]; then skip_next=0; continue; fi
    if [ "$a" = "--init_weights_from" ]; then skip_next=1; continue; fi
    PERSISTENT_ARGS+=("$a")
done

echo "=== superviseur demarre $(date -Iseconds) -- out=$OUT ===" >> "$LOG"
echo "args persistants (repasses a chaque relance) : ${PERSISTENT_ARGS[*]}" >> "$LOG"
# BUG CORRIGE (2026-07-26) : si le TOUT PREMIER lancement (avec
# --init_weights_from) plante AVANT d'ecrire le moindre checkpoint (ex.
# mauvais format de fichier -- code 1, pas un Xid), `$LAST` reste vide sur la
# relance et l'ancienne logique tombait dans le `else`, qui ne repassait PAS
# --init_weights_from -- la relance repartait alors sur `--init_nemo` par
# defaut (le tout premier checkpoint causal), PAS sur le poids demande.
# Constate : un cycle entier (des heures de GPU) a tourne sur le mauvais
# point de depart, silencieusement, sans aucune erreur visible. On repasse
# maintenant --init_weights_from a CHAQUE relance tant qu'aucun checkpoint
# n'existe encore (une fois qu'un `last.ckpt` existe, --resume_from prend le
# relais et --init_weights_from ne sert plus a rien, donc aucun risque de
# double-application).
INIT_WEIGHTS_ARGS=()
skip_next2=0
for a in "$@"; do
    if [ "$skip_next2" -eq 1 ]; then INIT_WEIGHTS_ARGS+=("$a"); skip_next2=0; continue; fi
    if [ "$a" = "--init_weights_from" ]; then INIT_WEIGHTS_ARGS+=("$a"); skip_next2=1; fi
done

FIRST=1
while true; do
    LAST=$(ls -t "$OUT"/last*.ckpt 2>/dev/null | head -1)
    if [ -n "$LAST" ]; then
        echo "reprise (etat complet) depuis : $LAST" >> "$LOG"
        RUN_ARGS=(--resume_from "$LAST" --out "$OUT" "${PERSISTENT_ARGS[@]}")
    elif [ "$FIRST" -eq 1 ]; then
        echo "premier lancement, args: $*" >> "$LOG"
        RUN_ARGS=(--out "$OUT" "$@")
    else
        echo "relance sans checkpoint existant -- re-application de --init_weights_from" >> "$LOG"
        RUN_ARGS=(--out "$OUT" "${PERSISTENT_ARGS[@]}" "${INIT_WEIGHTS_ARGS[@]}")
    fi
    FIRST=0
    /usr/bin/python3.14 finetune_streaming_causal.py "${RUN_ARGS[@]}" >> "$LOG" 2>&1
    CODE=$?
    if [ $CODE -eq 0 ]; then
        echo "=== termine normalement (code 0) $(date -Iseconds) ===" >> "$LOG"
        break
    fi
    echo "=== CRASH (code $CODE) $(date -Iseconds) -- relance dans 15s ===" >> "$LOG"
    sleep 15
done
