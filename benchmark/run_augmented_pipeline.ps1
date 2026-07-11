# Pipeline complet : SLR61 download → manifest → mix → training augmenté
# Chaque étape dépend de la précédente — arrêt si erreur.
# Log: benchmark/logs/augmented_pipeline.log

$PYTHON = "D:/Coran Karim/benchmark/.venv/Scripts/python.exe"
$BENCH  = "D:/Coran Karim/benchmark"
$LOG    = "$BENCH/logs/augmented_pipeline.log"
$SNAP   = "$BENCH/models/fastconformer-quran-pcd/fastconformer-quran-pcd-snapshot.nemo"
$CKPT_OUT = "$BENCH/models/fastconformer-quran-augmented"
$TRAIN_M = "$BENCH/augmented_manifests/train_augmented.jsonl"
$VAL_M   = "$BENCH/augmented_manifests/val_augmented.jsonl"

function Log($msg) {
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "$ts  $msg" | Tee-Object -FilePath $LOG -Append
}

Log "=== PIPELINE AUGMENTÉ DÉMARRÉ ==="

# Étape 1 — Téléchargement SLR61
Log "--- Étape 1/4 : téléchargement SLR61 ---"
& $PYTHON -X utf8 "$BENCH/download_slr61.py" 2>&1 | Tee-Object -FilePath $LOG -Append
if ($LASTEXITCODE -ne 0) { Log "ERREUR étape 1 — abandon."; exit 1 }

# Étape 2 — Manifest SLR61
Log "--- Étape 2/4 : manifest SLR61 → NeMo JSONL ---"
& $PYTHON -X utf8 "$BENCH/prepare_slr61_manifest.py" 2>&1 | Tee-Object -FilePath $LOG -Append
if ($LASTEXITCODE -ne 0) { Log "ERREUR étape 2 — abandon."; exit 1 }

# Étape 3 — Mix Coran + SLR61
Log "--- Étape 3/4 : mix Coran 80% + SLR61 20% ---"
& $PYTHON -X utf8 "$BENCH/prepare_augmented_manifest.py" `
    --slr61_ratio 0.20 `
    2>&1 | Tee-Object -FilePath $LOG -Append
if ($LASTEXITCODE -ne 0) { Log "ERREUR étape 3 — abandon."; exit 1 }

# Étape 4 — Entraînement (nouveau run, répertoire séparé, snapshot.nemo comme base)
Log "--- Étape 4/4 : entraînement FastConformer augmenté ---"
Log "  Resume  : $SNAP"
Log "  CkptDir : $CKPT_OUT"
Log "  Train   : $TRAIN_M"
Log "  Val     : $VAL_M"

& $PYTHON -X utf8 "$BENCH/finetune_fastconformer.py" `
    --train_manifest $TRAIN_M `
    --val_manifest   $VAL_M `
    --resume         $SNAP `
    --ckpt_dir       $CKPT_OUT `
    --epochs 10 `
    --batch_size 8 `
    --lr 5e-5 `
    --num_workers 0 `
    2>&1 | Tee-Object -FilePath $LOG -Append

if ($LASTEXITCODE -ne 0) { Log "ERREUR étape 4."; exit 1 }
Log "=== PIPELINE TERMINÉ ==="
