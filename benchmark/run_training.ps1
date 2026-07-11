# Pipeline : Small FT → Medium FT → Benchmark quantification
# Utilise train_combined.jsonl si disponible (après alignement YouTube)
# Usage : .\run_training.ps1

Set-Location $PSScriptRoot
$LogDir = "logs"
New-Item -ItemType Directory -Force $LogDir | Out-Null

function Run-Step {
    param($Label, $Script, $LogFile)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "ETAPE : $Label" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    $start = Get-Date
    $env:PYTHONIOENCODING = "utf-8"
    python $Script 2>&1 | Tee-Object -FilePath "$LogDir\$LogFile"
    $elapsed = (Get-Date) - $start
    Write-Host "Duree : $($elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor Green
}

# Afficher le dataset utilisé
$combined = "data\train_combined.jsonl"
$orig     = "data\train_full.jsonl"
if (Test-Path $combined) {
    $count = (Get-Content $combined | Measure-Object -Line).Lines
    Write-Host "Dataset : train_combined.jsonl ($count clips)" -ForegroundColor Green
} elseif (Test-Path $orig) {
    $count = (Get-Content $orig | Measure-Object -Line).Lines
    Write-Host "Dataset : train_full.jsonl ($count clips) - YouTube non encore aligne" -ForegroundColor Yellow
} else {
    Write-Host "ERREUR : aucun dataset trouve" -ForegroundColor Red
    exit 1
}

# 1. Whisper Small FT (~4h avec données combinées)
Run-Step "Whisper Small Fine-Tune (244M)" "whisper_finetune_small.py" "small_ft.log"

if (-not (Test-Path "models\whisper-small-ft")) {
    Write-Host "ERREUR : whisper-small-ft absent, arret." -ForegroundColor Red
    exit 1
}
Write-Host "Whisper Small FT OK -> models\whisper-small-ft" -ForegroundColor Green

# 2. Whisper Medium FT (~7h)
Run-Step "Whisper Medium Fine-Tune (769M)" "whisper_finetune_medium.py" "medium_ft.log"

# 3. Benchmark quantification
Run-Step "Benchmark Quantification" "whisper_quant_benchmark.py" "quant_bench.log"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "PIPELINE COMPLET" -ForegroundColor Green
Write-Host "Resultats -> results\quant_benchmark.csv" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
