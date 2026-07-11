# Pipeline complet : YouTube Align → Whisper Small FT → Medium FT → Benchmark
# Usage : .\run_small_medium.ps1
# Temps total estimé : ~12-13h
#   Alignement YouTube  ~50 min
#   Whisper Small       ~3h45 (dataset élargi)
#   Whisper Medium      ~7h
#   Benchmark quant     ~1h

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
    python $Script 2>&1 | Tee-Object -FilePath "$LogDir\$LogFile"
    $elapsed = (Get-Date) - $start
    Write-Host "Durée : $($elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor Green
}

# 0. Alignement YouTube (segments + transcription + matching)
Run-Step "YouTube Alignment" "youtube_align.py" "youtube_align.log"

$combined = "data\train_combined.jsonl"
if (Test-Path $combined) {
    $count = (Get-Content $combined | Measure-Object -Line).Lines
    Write-Host "train_combined.jsonl : $count clips" -ForegroundColor Green
} else {
    Write-Host "AVERTISSEMENT : train_combined.jsonl absent — Small/Medium utiliseront train_full.jsonl" -ForegroundColor Yellow
}

# 1. Whisper Small FT (244M, ~3h45 avec données combinées)
Run-Step "Whisper Small Fine-Tune" "whisper_finetune_small.py" "small_ft.log"

if (-not (Test-Path "models\whisper-small-ft")) {
    Write-Host "ERREUR : whisper-small-ft absent, arrêt." -ForegroundColor Red
    exit 1
}

# 2. Whisper Medium FT (769M, ~7h)
Run-Step "Whisper Medium Fine-Tune" "whisper_finetune_medium.py" "medium_ft.log"

# 3. Benchmark quantification (tous les modèles disponibles)
Run-Step "Benchmark Quantification" "whisper_quant_benchmark.py" "quant_bench.log"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "PIPELINE COMPLET" -ForegroundColor Green
Write-Host "Résultats → results\quant_benchmark.csv" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
