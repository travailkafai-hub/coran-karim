$ErrorActionPreference = "Continue"
$py = "D:\Coran Karim\benchmark\.venv\Scripts\python.exe"
$env:PYTHONUTF8 = "1"; $env:PYTHONIOENCODING = "utf-8"
$env:HF_HOME = "D:\Coran Karim\benchmark\.hf"
$env:HF_HUB_OFFLINE = "1"
Set-Location "D:\Coran Karim\benchmark"

function Stage($m) { Write-Output "=====STAGE===== $m" }

# -- 1. Split full dataset
Stage "Split full dataset (train_full / test_voice_full / test_text_full)"
& $py split_full.py
if ($LASTEXITCODE -ne 0) { Write-Error "split_full.py failed"; exit 1 }

# -- 2. Baseline sur test_full (pour comparaison post-FT)
Stage "BASE Whisper - test_voice_full (sample 200)"
& $py eval_ft.py whisper "tarteel-ai/whisper-base-ar-quran" test_voice_full.jsonl 200 2>&1 | Select-String "RESULT"
Stage "BASE Whisper - test_text_full (sample 200)"
& $py eval_ft.py whisper "tarteel-ai/whisper-base-ar-quran" test_text_full.jsonl 200 2>&1 | Select-String "RESULT"

# -- 3. Fine-tune Whisper sur Coran complet
Stage "Whisper FT full Quran (2 epochs, encoder degage, lr 1e-5)"
Remove-Item -Recurse -Force "models\whisper-full-ft" -ErrorAction SilentlyContinue
$env:HF_HUB_OFFLINE = "0"
& $py whisper_finetune_full.py 2>&1 | Select-String "WHISPER FULL FT DONE|'loss'"
$env:HF_HUB_OFFLINE = "1"
if ($LASTEXITCODE -ne 0) { Write-Error "whisper_finetune_full.py failed"; exit 1 }

# -- 4. Eval post-FT
Stage "FT Whisper full - test_voice_full (sample 200)"
& $py eval_ft.py whisper "models\whisper-full-ft" test_voice_full.jsonl 200 2>&1 | Select-String "RESULT"
Stage "FT Whisper full - test_text_full (sample 200)"
& $py eval_ft.py whisper "models\whisper-full-ft" test_text_full.jsonl 200 2>&1 | Select-String "RESULT"

# -- 5. Comparaison rapide sur l'ancien test set (voix Phase 2)
Stage "FT Whisper full - test_voice Phase2 (80 clips)"
& $py eval_ft.py whisper "models\whisper-full-ft" test_voice.jsonl 80 2>&1 | Select-String "RESULT"
Stage "FT Whisper full - test_text Phase2 (80 clips)"
& $py eval_ft.py whisper "models\whisper-full-ft" test_text.jsonl 80 2>&1 | Select-String "RESULT"

Stage "PHASE 3 ALL DONE"
