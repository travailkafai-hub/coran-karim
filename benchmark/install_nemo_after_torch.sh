#!/bin/bash
# À exécuter après que PyTorch soit compilé

echo "=== Post-PyTorch: Installation NeMo + Dépendances ==="

cd /mnt/ssd5/Coran\ Karim/benchmark
source .venv_py314/bin/activate

echo "⏳ Installation NeMo toolkit..."
pip install nemo_toolkit[asr] pytorch-lightning omegaconf -q

echo "⏳ Vérification..."
python3 -c "import torch, nemo.collections.asr; print(f'✅ PyTorch {torch.__version__} + NeMo OK')" && \
echo "" && \
echo "=== Prêt pour fine-tuning ! ===" && \
echo "Commande:" && \
echo "python3 finetune_fastconformer.py --epochs 2 --batch_size 8 --lr 1e-5 \\" && \
echo "  --resume models/fastconformer-quran-tajweed/fastconformer-quran-epoch=09-val_wer_ctc=0.058.ckpt \\" && \
echo "  --train_manifest nemo_manifests/train_manifest_augmented_ubuntu.jsonl \\" && \
echo "  --val_manifest nemo_manifests/val_manifest_ubuntu.jsonl \\" && \
echo "  --ckpt_dir models/fastconformer-quran-tajweed-augmented"
