#!/bin/bash
LOG_CUR="logs/gemma_islamic_v6.log"
echo "$(date) - watching $LOG_CUR for completion..."
until grep -q "GEMMA TUTOR LORA DONE" "$LOG_CUR" 2>/dev/null; do
  sleep 60
done
echo "$(date) - current run finished, launching enriched-dataset run"
export GEMMA_SFT="data/gemma_islamic_sft_v2.jsonl"
export GEMMA_OUT="models/gemma-4-E2B-tutor-lora-v2"
"D:/Coran Karim/benchmark/.venv/Scripts/python.exe" gemma_finetune_tutor.py 30000 > logs/gemma_tutor_v2dataset.log 2>&1
echo "$(date) - enriched run finished (exit $?)"
