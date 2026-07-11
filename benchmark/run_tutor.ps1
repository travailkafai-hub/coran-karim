$ErrorActionPreference = "Continue"
$py = "D:\Coran Karim\benchmark\.venv\Scripts\python.exe"
$env:PYTHONUTF8 = "1"; $env:PYTHONIOENCODING = "utf-8"
$env:HF_HOME = "D:\Coran Karim\benchmark\.hf"
$env:HF_HUB_OFFLINE = "1"
Set-Location "D:\Coran Karim\benchmark"

function Stage($m) { Write-Output "=====STAGE===== $m" }

# -- 1. Fine-tune Gemma as text tutor (30k examples, 2 epochs)
Stage "Gemma text tutor LoRA (30k ex, 2 epochs)"
Remove-Item -Recurse -Force "models\gemma-4-E2B-tutor-lora" -ErrorAction SilentlyContinue
& $py gemma_finetune_tutor.py 30000 2>&1 | Select-String "GEMMA TUTOR LORA DONE|ep[0-9] step"

if ($LASTEXITCODE -ne 0) { Write-Error "gemma_finetune_tutor.py failed"; exit 1 }

# -- 2. Quick smoke test: ask the tutor to explain 3 verses
Stage "Smoke test tutor (3 versets)"
$test_script = @"
import truststore; truststore.inject_into_ssl()
import os, torch
os.environ['HF_HUB_OFFLINE'] = '1'
ROOT = r'D:\Coran Karim\benchmark'
M = os.path.join(ROOT, 'models', 'gemma-4-E2B-it')
LORA = os.path.join(ROOT, 'models', 'gemma-4-E2B-tutor-lora')
from transformers import AutoProcessor, AutoModelForMultimodalLM
from peft import PeftModel
proc = AutoProcessor.from_pretrained(M)
model = AutoModelForMultimodalLM.from_pretrained(M, dtype=torch.bfloat16, device_map='cuda')
model = PeftModel.from_pretrained(model, LORA).eval()
SYSTEM = 'Tu es un tuteur specialise en memorisation et comprehension du Coran.'
QUESTIONS = [
    ('1:1', 'Quel est le sens du verset 1:1 du Coran ?'),
    ('112:1', 'Explique le verset 112:1 du Coran en francais.'),
    ('2:255', 'Que signifie le verset 2:255 (Ayat al-Kursi) ?'),
]
for key, q in QUESTIONS:
    msgs = [
        {'role': 'system', 'content': [{'type': 'text', 'text': SYSTEM}]},
        {'role': 'user',   'content': [{'type': 'text', 'text': q}]},
    ]
    enc = proc.apply_chat_template(msgs, tokenize=True, return_dict=True, return_tensors='pt',
                                   add_generation_prompt=True).to('cuda')
    with torch.no_grad():
        out = model.generate(**enc, max_new_tokens=200, do_sample=False, repetition_penalty=1.1)
    il = enc['input_ids'].shape[-1]
    ans = proc.decode(out[0][il:], skip_special_tokens=True).strip()
    print(f'\n=== {key} ===')
    print(f'Q: {q}')
    print(f'A: {ans[:400]}')
"@
$test_script | & $py -

Stage "TUTOR ALL DONE"
