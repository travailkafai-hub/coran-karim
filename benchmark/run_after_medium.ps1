# Enchainement POST-MEDIUM (ne touche pas au GPU tant que Medium tourne)
#   1. Attend la fin de Medium (poll du log)
#   2. Lance la continuation de Small (reprise ckpt-12000, 4 epoques, patience 8)
#   3. Benchmark quantification (compare Small+Medium)
# Small n'avait pas fini ses epoques + loss encore en baisse -> on continue.

Set-Location $PSScriptRoot
$env:PYTHONIOENCODING = "utf-8"; $env:PYTHONUTF8 = "1"
$py = if (Test-Path ".venv\Scripts\python.exe") { ".venv\Scripts\python.exe" } else { "python" }

function Stage($m) { Write-Host ""; Write-Host "===== [$(Get-Date -Format 'HH:mm')] $m =====" -ForegroundColor Cyan }

# ---------------------------------------------------------------------
# 1. Attendre la fin de Medium
# ---------------------------------------------------------------------
Stage "Attente fin de Whisper Medium..."
while (-not (Select-String -Path "logs\medium_ft.log" -Pattern "WHISPER MEDIUM FT DONE" -Quiet -ErrorAction SilentlyContinue)) {
    Start-Sleep -Seconds 60
}
Stage "Medium TERMINE"
Start-Sleep -Seconds 10   # laisser le GPU se liberer

# ---------------------------------------------------------------------
# 2. Continuation de Small (reprise du dernier checkpoint, 4 epoques)
# ---------------------------------------------------------------------
Stage "Continuation Whisper Small (reprise, 4 epoques)"
& $py whisper_finetune_small.py 2>&1 | Tee-Object "logs\small_ft_continue.log"

# ---------------------------------------------------------------------
# 3. Benchmark (Small + Medium)
# ---------------------------------------------------------------------
Stage "Benchmark quantification"
& $py whisper_quant_benchmark.py 2>&1 | Tee-Object "logs\quant_bench.log"

Stage "ENCHAINEMENT POST-MEDIUM TERMINE"
Write-Host "AFTER MEDIUM DONE" -ForegroundColor Green
