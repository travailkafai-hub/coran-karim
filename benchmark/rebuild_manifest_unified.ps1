# Reconstruit manifest_unified.jsonl depuis tous les JSONL D: + E:
# puis relance prepare_nemo_data.py pour les manifests NeMo
# Usage: .\rebuild_manifest_unified.ps1

$env:PYTHONIOENCODING = "utf-8"
Set-Location "D:\Coran Karim\benchmark"

function Log($msg) { Write-Output "[$((Get-Date).ToString('HH:mm:ss'))] $msg" }

Log "=== REBUILD MANIFEST UNIFIED ==="
Log "D: libre: $([math]::Round((Get-PSDrive D).Free/1GB,1)) GB"

.\.venv\Scripts\python -X utf8 -c @"
import json, sys
from pathlib import Path
sys.stdout.reconfigure(encoding='utf-8')

sources = [
    Path('D:/Coran Karim/benchmark/data/manifest_full_wav.jsonl'),
    Path('D:/Coran Karim/benchmark/data/train_Husary_Muallim_128kbps.jsonl'),
    Path('D:/Coran Karim/benchmark/data/train_OmarQazabri_128kbps.jsonl'),
]
sources += sorted(Path('D:/Coran Karim/benchmark/data').glob('train_*_assajda.jsonl'))
if Path('E:/Coran_data').exists():
    sources += sorted(Path('E:/Coran_data').glob('train_*_assajda.jsonl'))

all_entries = []
seen_keys = set()
for src in sources:
    if not src.exists():
        print(f'SKIP: {src.name}')
        continue
    n = 0
    with open(src, encoding='utf-8') as f:
        for line in f:
            try:
                e = json.loads(line)
                dedup_key = e.get('reciter','') + '-' + e.get('key','')
                if dedup_key not in seen_keys:
                    seen_keys.add(dedup_key)
                    all_entries.append(e)
                    n += 1
            except: pass
    print(f'  {src.name}: {n} entrees')

out = Path('D:/Coran Karim/benchmark/data/manifest_unified.jsonl')
with open(out, 'w', encoding='utf-8') as f:
    for e in all_entries:
        f.write(json.dumps(e, ensure_ascii=False) + '\n')
print(f'TOTAL: {len(all_entries)} entrees -> {out.name}')
"@ 2>&1

Log "Reconstruction manifest_unified.jsonl terminee"
Log "Lancement prepare_nemo_data.py..."
.\.venv\Scripts\python -X utf8 prepare_nemo_data.py --manifest "data\manifest_unified.jsonl" 2>&1
Log "=== REBUILD TERMINE ==="
