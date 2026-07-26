#!/usr/bin/env bash
# Superviseur pour finetune_nemotron_ctc.py -- meme risque de crash GPU (Xid 8,
# extinction physique de l'ecran) que supervise_causal_training.sh, et MEME
# BUG DEJA CORRIGE a reproduire ici : les hyperparametres fixes doivent etre
# repasses a CHAQUE relance, pas seulement la premiere, sinon une reprise
# retombe sur les defauts du script (cf. supervise_causal_training.sh,
# 2026-07-26, 16 epochs perdues silencieusement la premiere fois).
set -uo pipefail
cd "$(dirname "$0")"

OUT="$1"; shift
mkdir -p "$OUT"
LOG="$OUT/supervised.log"

PERSISTENT_ARGS=()
for a in "$@"; do PERSISTENT_ARGS+=("$a"); done

FIRST=1
while true; do
    LAST=$(ls -t "$OUT"/last*.ckpt 2>/dev/null | head -1)
    if [ -n "$LAST" ]; then
        RUN_ARGS=(--resume_from "$LAST" --out "$OUT" "${PERSISTENT_ARGS[@]}")
    else
        RUN_ARGS=(--out "$OUT" "${PERSISTENT_ARGS[@]}")
    fi
    FIRST=0
    PYTHONUNBUFFERED=1 ./.venv_nemotron_ft/bin/python3.13 finetune_nemotron_ctc.py "${RUN_ARGS[@]}" >> "$LOG" 2>&1
    CODE=$?
    [ $CODE -eq 0 ] && break
    echo "$(date '+%Y-%m-%d %H:%M:%S') -- crash (code=$CODE), relance dans 15s" >> "$LOG"
    sleep 15
done
echo "$(date '+%Y-%m-%d %H:%M:%S') -- termine (code 0)" >> "$LOG"
