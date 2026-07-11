# Retrain FastConformer avec le manifest unifie (apres que overnight_pipeline.ps1 finisse)
# Lance ce script apres que overnight_pipeline.ps1 soit termine.
# Usage: .\retrain_unified.ps1

$env:PYTHONIOENCODING = "utf-8"
Set-Location "D:\Coran Karim\benchmark"

function Log($msg) {
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Output "[$ts] $msg"
}

Log "=== RETRAIN UNIFIE ==="
Log "Verification manifest unifie..."

if (-not (Test-Path "data\manifest_unified.jsonl")) {
    Log "ERREUR: manifest_unified.jsonl non trouve!"
    Log "Lance d abord overnight_pipeline.ps1"
    exit 1
}

$lines = (Get-Content "data\manifest_unified.jsonl" | Measure-Object -Line).Lines
Log "manifest_unified.jsonl: $lines clips"
Log "D: libre: $([math]::Round((Get-PSDrive D).Free/1GB,1)) GB"

Log "Preparation manifests NeMo (unified)..."
.\.venv\Scripts\python prepare_nemo_data.py --manifest "data\manifest_unified.jsonl" 2>&1

Log "Lancement fine-tuning FastConformer (manifest unifie)..."
.\.venv\Scripts\python finetune_fastconformer.py --epochs 10 --batch_size 8 2>&1 | Tee-Object "logs\fastconformer_unified.log"

Log "=== TRAINING UNIFIE TERMINE ==="
