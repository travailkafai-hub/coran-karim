# Launcher standalone : fine-tune wav2vec2 CTC (forced-aligner Coran)
# A lancer APRES le pipeline principal (GPU libre). N'entraine QUE le CTC.
# Usage : .\run_ctc.ps1

Set-Location $PSScriptRoot
$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONUTF8 = "1"
New-Item -ItemType Directory -Force "logs" | Out-Null
$py = if (Test-Path ".venv\Scripts\python.exe") { ".venv\Scripts\python.exe" } else { "python" }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[$(Get-Date -Format 'HH:mm')] wav2vec2 CTC forced-aligner (Coran)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Construire le vocab si absent
if (-not (Test-Path "data\wav2vec2_vocab.json")) {
    & $py wav2vec2_make_vocab.py 2>&1 | Tee-Object "logs\w2v_vocab.log"
}

$t = Get-Date
& $py wav2vec2_finetune_ctc.py 2>&1 | Tee-Object "logs\wav2vec2_ctc.log"
Write-Host "CTC duree: $((Get-Date) - $t)" -ForegroundColor Green
Write-Host "CTC PIPELINE DONE -> models\wav2vec2-quran-ctc" -ForegroundColor Green
