#!/bin/bash
cd /mnt/ssd5/Coran\ Karim/benchmark

python3 finetune_fastconformer.py \
  --epochs 2 \
  --batch_size 8 \
  --lr 1e-5 \
  --resume "models/fastconformer-quran-tajweed/fastconformer-quran-epoch=09-val_wer_ctc=0.058.ckpt" \
  --train_manifest "nemo_manifests/train_manifest_augmented_ubuntu.jsonl" \
  --val_manifest "nemo_manifests/val_manifest_ubuntu.jsonl" \
  --ckpt_dir "models/fastconformer-quran-tajweed-augmented" \
  2>&1 | tee logs/finetune_augmented_ubuntu_$(date +%Y%m%d_%H%M%S).log
