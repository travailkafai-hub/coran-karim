# Pipeline ENTRAINEMENT SEUL (alignement deja fait, train_combined.jsonl pret)
#   Whisper Small FT -> Medium FT -> Benchmark quantification
# Usage : .\run_training_only.ps1
# Temps estime : Small ~4h + Medium ~7h + bench ~1h = ~12h

Set-Location $PSScriptRoot
$env:PYTHONIOENCODING = "utf-8"
$LogDir = "logs"
New-Item -ItemType Directory -Force $LogDir | Out-Null

function Run-Step {
    param($Label, $Script, $LogFile)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "ETAPE : $Label" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    $start = Get-Date
    python $Script 2>&1 | Tee-Object -FilePath "$LogDir\$LogFile"
    $elapsed = (Get-Date) - $start
    Write-Host "Duree : $($elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor Green
}

# Verif dataset combine
$combined = "data\train_combined.jsonl"
if (Test-Path $combined) {
    $count = (Get-Content $combined | Measure-Object -Line).Lines
    Write-Host "Dataset : train_combined.jsonl ($count clips)" -ForegroundColor Green
} else {
    Write-Host "AVERTISSEMENT : train_combined.jsonl absent -> fallback train_full.jsonl" -ForegroundColor Yellow
}

# 1. Whisper Small FT
Run-Step "Whisper Small Fine-Tune" "whisper_finetune_small.py" "small_ft.log"
if (-not (Test-Path "models\whisper-small-ft")) {
    Write-Host "ERREUR : whisper-small-ft absent, arret." -ForegroundColor Red
    exit 1
}

# 2. Whisper Medium FT
Run-Step "Whisper Medium Fine-Tune" "whisper_finetune_medium.py" "medium_ft.log"

# 3. Benchmark quantification (5 configs x 2 test sets)
Run-Step "Benchmark Quantification" "whisper_quant_benchmark.py" "quant_bench.log"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "PIPELINE ENTRAINEMENT COMPLET" -ForegroundColor Green
Write-Host "Resultats -> results\quant_benchmark.csv" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
