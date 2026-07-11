$ErrorActionPreference="Continue"
$py="D:\Coran Karim\benchmark\.venv\Scripts\python.exe"
$env:PYTHONUTF8="1"; $env:PYTHONIOENCODING="utf-8"; $env:HF_HOME="D:\Coran Karim\benchmark\.hf"
Set-Location "D:\Coran Karim\benchmark"
function Stage($m){ Write-Output "=====STAGE===== $m" }

Stage "BASE Whisper - voix"
& $py eval_ft.py whisper "tarteel-ai/whisper-base-ar-quran" test_voice.jsonl 80 2>&1 | Select-String "RESULT"
Stage "BASE Whisper - texte"
& $py eval_ft.py whisper "tarteel-ai/whisper-base-ar-quran" test_text.jsonl 80 2>&1 | Select-String "RESULT"

Stage "BASE Gemma - voix"
$env:HF_HUB_OFFLINE="1"
& $py eval_ft.py gemma "models\gemma-4-E2B-it" test_voice.jsonl 60 2>&1 | Select-String "RESULT"
Stage "BASE Gemma - texte"
& $py eval_ft.py gemma "models\gemma-4-E2B-it" test_text.jsonl 60 2>&1 | Select-String "RESULT"

Stage "FT Whisper (1 epoch, encodeur gele, lr 6e-6)"
Remove-Item -Recurse -Force "models\whisper-base-ft" -ErrorAction SilentlyContinue
$env:HF_HUB_OFFLINE="0"
& $py whisper_finetune.py 2>&1 | Select-String "WHISPER FT DONE|loss'"
$env:HF_HUB_OFFLINE="1"
Stage "FT Whisper EVAL - voix"
& $py eval_ft.py whisper "models\whisper-base-ft" test_voice.jsonl 80 2>&1 | Select-String "RESULT"
Stage "FT Whisper EVAL - texte"
& $py eval_ft.py whisper "models\whisper-base-ft" test_text.jsonl 80 2>&1 | Select-String "RESULT"

Stage "FT Gemma LoRA (12000 ex)"
Remove-Item -Recurse -Force "models\gemma-4-E2B-lora" -ErrorAction SilentlyContinue
& $py gemma_finetune.py 12000 2>&1 | Select-String "GEMMA LORA DONE|step "
Stage "FT Gemma EVAL - voix"
& $py eval_ft.py gemma "models\gemma-4-E2B-it" test_voice.jsonl 60 "models\gemma-4-E2B-lora" 2>&1 | Select-String "RESULT"
Stage "FT Gemma EVAL - texte"
& $py eval_ft.py gemma "models\gemma-4-E2B-it" test_text.jsonl 60 "models\gemma-4-E2B-lora" 2>&1 | Select-String "RESULT"

Stage "ALL DONE"
