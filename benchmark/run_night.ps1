# =====================================================================
# PIPELINE NUIT — autonome, auto-recover
# ORDRE (modifie 2026-06-29) : Medium AVANT Gemma
#   1. Whisper Small FT        (reprend du dernier checkpoint)
#   2. Whisper Medium FT       (coute que coute -> SAFE_MODE si OOM)
#   3. Benchmark quantification (tous modeles Whisper)
#   4. Corpus islamique -> SFT + Gemma retrain   (en dernier)
# Chaque etape : log dedie, on continue meme si une etape echoue.
# =====================================================================

Set-Location $PSScriptRoot
$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONUTF8 = "1"
$LogDir = "logs"
New-Item -ItemType Directory -Force $LogDir | Out-Null
# .venv = environnement complet (torch CUDA, transformers, soundfile, jiwer, peft)
$py = if (Test-Path ".venv\Scripts\python.exe") { ".venv\Scripts\python.exe" } else { "python" }

function Stage($msg) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "[$(Get-Date -Format 'HH:mm')] $msg" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------
# 1. WHISPER SMALL FT (reprend du dernier checkpoint si present)
# ---------------------------------------------------------------------
Stage "1/4 Whisper Small FT (dataset combine, reprise auto)"
$t = Get-Date
& $py whisper_finetune_small.py 2>&1 | Tee-Object "$LogDir\small_ft.log"
Write-Host "Small FT duree: $((Get-Date) - $t)" -ForegroundColor Green

# ---------------------------------------------------------------------
# 2. WHISPER MEDIUM FT (coute que coute : SAFE_MODE si echec)
# ---------------------------------------------------------------------
Stage "2/4 Whisper Medium FT"
$t = Get-Date
& $py whisper_finetune_medium.py 2>&1 | Tee-Object "$LogDir\medium_ft.log"
if (-not (Test-Path "models\whisper-medium-ft")) {
    Stage "2/4 Medium a echoue -> retry SAFE_MODE (OOM recovery)"
    $env:WHISPER_SAFE_MODE = "1"
    & $py whisper_finetune_medium.py 2>&1 | Tee-Object "$LogDir\medium_ft_safe.log"
    Remove-Item Env:\WHISPER_SAFE_MODE -ErrorAction SilentlyContinue
}
Write-Host "Medium FT duree: $((Get-Date) - $t)" -ForegroundColor Green

# ---------------------------------------------------------------------
# 3. BENCHMARK QUANTIFICATION (modeles Whisper)
# ---------------------------------------------------------------------
Stage "3/4 Benchmark quantification (5 configs x 2 test sets)"
& $py whisper_quant_benchmark.py 2>&1 | Tee-Object "$LogDir\quant_bench.log"

# ---------------------------------------------------------------------
# 4. CORPUS ISLAMIQUE -> SFT -> GEMMA RETRAIN (en dernier)
# ---------------------------------------------------------------------
Stage "4a/4 Construction SFT islamique (tafsir + hadith)"
& $py gemma_make_islamic_sft.py 2>&1 | Tee-Object "$LogDir\islamic_sft.log"

Stage "4b/4 Fusion datasets SFT -> gemma_combined_sft.jsonl"
$comb = "data\gemma_combined_sft.jsonl"
Remove-Item $comb -ErrorAction SilentlyContinue
if (Test-Path "data\gemma_tutor_sft.jsonl")   { Get-Content "data\gemma_tutor_sft.jsonl"   | Add-Content $comb }
if (Test-Path "data\gemma_islamic_sft.jsonl") { Get-Content "data\gemma_islamic_sft.jsonl" | Add-Content $comb }
if (Test-Path $comb) {
    $n = (Get-Content $comb | Measure-Object -Line).Lines
    Write-Host "Dataset combine Gemma: $n exemples" -ForegroundColor Green
}

Stage "4c/4 Gemma retrain (corpus islamique enrichi)"
$t = Get-Date
$env:GEMMA_SFT = "$PWD\data\gemma_combined_sft.jsonl"
$env:GEMMA_OUT = "$PWD\models\gemma-4-E2B-islamic-lora"
Remove-Item -Recurse -Force "models\gemma-4-E2B-islamic-lora" -ErrorAction SilentlyContinue
$gpy = if (Test-Path ".venv\Scripts\python.exe") { ".venv\Scripts\python.exe" } else { "python" }
& $gpy gemma_finetune_tutor.py 60000 2>&1 | Tee-Object "$LogDir\gemma_islamic.log"
Write-Host "Gemma retrain duree: $((Get-Date) - $t)" -ForegroundColor Green
Remove-Item Env:\GEMMA_SFT, Env:\GEMMA_OUT -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------
# 5. WAV2VEC2 CTC (forced-aligner pour validation temps-reel mot-par-mot)
# ---------------------------------------------------------------------
Stage "5/5 wav2vec2 CTC forced-aligner (Coran)"
$t = Get-Date
if (-not (Test-Path "data\wav2vec2_vocab.json")) {
    & $py wav2vec2_make_vocab.py 2>&1 | Tee-Object "$LogDir\w2v_vocab.log"
}
& $py wav2vec2_finetune_ctc.py 2>&1 | Tee-Object "$LogDir\wav2vec2_ctc.log"
Write-Host "CTC duree: $((Get-Date) - $t)" -ForegroundColor Green

Stage "PIPELINE NUIT TERMINEE"
Write-Host "Modeles : whisper-small-ft, whisper-medium-ft, gemma-4-E2B-islamic-lora, wav2vec2-quran-ctc" -ForegroundColor Green
Write-Host "Benchmark : results\quant_benchmark.csv" -ForegroundColor Green
Write-Host "NIGHT PIPELINE DONE" -ForegroundColor Green
