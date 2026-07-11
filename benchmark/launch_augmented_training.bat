@echo off
REM =============================================================================
REM  NOUVEAU RUN FastConformer — dataset augmenté (Coran + SLR61)
REM  Objectif : corriger le biais "correction vers texte canonique"
REM
REM  Prérequis :
REM    1. python download_slr61.py            ← télécharge SLR61
REM    2. python prepare_slr61_manifest.py    ← convertit en NeMo JSONL
REM    3. python prepare_augmented_manifest.py ← mix 80% Coran + 20% SLR61
REM    4. ce script                           ← lance l'entraînement
REM
REM  Stratégie de départ :
REM    --resume snapshot.nemo → repart des poids du run actuel (val_wer_ctc 1.64%)
REM    mais avec un NOUVEL optimiseur + nouveau scheduler cosine.
REM    Si tu veux repartir du modèle NVIDIA original, retire --resume.
REM =============================================================================

set PYTHON="D:/Coran Karim/benchmark/.venv/Scripts/python.exe"
set SCRIPT="D:/Coran Karim/benchmark/finetune_fastconformer.py"
set TRAIN_MANIFEST="D:/Coran Karim/benchmark/augmented_manifests/train_augmented.jsonl"
set VAL_MANIFEST="D:/Coran Karim/benchmark/augmented_manifests/val_augmented.jsonl"
set SNAPSHOT="D:/Coran Karim/benchmark/models/fastconformer-quran-pcd/fastconformer-quran-pcd-snapshot.nemo"
set LOG="D:/Coran Karim/benchmark/logs/augmented_run.log"

REM Crée le répertoire de logs si nécessaire
if not exist "D:\Coran Karim\benchmark\logs\" mkdir "D:\Coran Karim\benchmark\logs\"

echo.
echo ============================================================
echo  Lancement : FastConformer — run augmenté
echo  Train    : %TRAIN_MANIFEST%
echo  Val      : %VAL_MANIFEST%
echo  Resume   : %SNAPSHOT%
echo  Log      : %LOG%
echo ============================================================
echo.

%PYTHON% -X utf8 %SCRIPT% ^
    --train_manifest %TRAIN_MANIFEST% ^
    --val_manifest   %VAL_MANIFEST% ^
    --resume         %SNAPSHOT% ^
    --epochs         10 ^
    --batch_size     8 ^
    --lr             5e-5 ^
    --num_workers    0 ^
    --max_duration   30.0 ^
    > %LOG% 2>&1

echo.
echo Terminé. Log : %LOG%
