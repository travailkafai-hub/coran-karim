# Pipeline nocturne automatisé - Coran Karim Dataset
# Enchaine: Batch1 -> Batch2 (E:) -> Manifest -> NeMo prep
# Usage: .\overnight_pipeline.ps1

$env:PYTHONIOENCODING = "utf-8"
Set-Location "D:\Coran Karim\benchmark"

function Log($msg) {
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Output "[$ts] $msg"
    Add-Content "logs\overnight.log" "[$ts] $msg"
}

function Wait-Process-Done($procId) {
    while ($true) {
        $alive = Get-Process -Id $procId -ErrorAction SilentlyContinue
        if (-not $alive) { return }
        Start-Sleep -Seconds 60
    }
}

function Count-JsonlLines($path) {
    if (-not (Test-Path $path)) { return 0 }
    return (Get-Content $path | Measure-Object -Line).Lines
}

New-Item -ItemType Directory -Path "logs" -Force | Out-Null
Log "=== PIPELINE NOCTURNE DÉMARRÉ ==="
Log "D: libre: $([math]::Round((Get-PSDrive D).Free/1GB, 1)) GB"
Log "E: libre: $([math]::Round((Get-PSDrive E).Free/1GB, 1)) GB"

# ──────────────────────────────────────────────────────────────────────────────
# PHASE 1 : Attendre fin du Batch 1 (PID 34544 ou premier process python lourd)
# ──────────────────────────────────────────────────────────────────────────────
Log "PHASE 1 : Attente fin Batch 1 (download assajda sur D:)..."
$batch1Pid = 34544  # PID observé du process en cours
Wait-Process-Done $batch1Pid

Log "Batch 1 terminé (ou arrêté faute d'espace)"
$jsonls = Get-ChildItem "data\train_*_assajda.jsonl" | Where-Object { (Get-Content $_.FullName | Measure-Object -Line).Lines -gt 100 }
Log "Réciteurs batch 1 complétés: $($jsonls.Count)"
foreach ($f in $jsonls) {
    Log "  $($f.Name.Replace('train_','').Replace('_assajda.jsonl',''))"
}
Log "D: libre: $([math]::Round((Get-PSDrive D).Free/1GB, 1)) GB"

# ──────────────────────────────────────────────────────────────────────────────
# PHASE 2 : Batch 2 sur E: (30 reciters)
# ──────────────────────────────────────────────────────────────────────────────
Log "PHASE 2 : Lancement Batch 2 -> E:\Coran_data..."
New-Item -ItemType Directory -Path "E:\Coran_data" -Force | Out-Null

$reciters2 = "ZakariaHamama,IdrissAbkar,KhalidAlJalil,AlzainMohamedAhmed," +
             "MohamedKantaoui,MohamedHamdan,YoussefEdghouch,NurdinMaghriby,RachidIfrad," +
             "MohamedAlJabery,AbdelhamidHssain,AbdelKabirHadidi,SamirBelaachya,MohamedElIraoui," +
             "MohamedChahboun,RachidBelaachya,FaysalWizar,AbdurrahimNabulsi,HosseinBousseksso," +
             "AbdallahMatroud,AbdulRashidSufi,AbdulWadudHaneef,AhmedSaoud,MohamedElBarak," +
             "MohamedAlMohisni,MustaphaLahouni,AntarMuslim,SaberAbdulHakam,HassanSaleh,AbdallahKamel"

$batch2Proc = Start-Process -NoNewWindow -FilePath ".\.venv\Scripts\python" `
  -ArgumentList "download_assajda.py","--reciter",$reciters2,"--data-dir","E:\Coran_data" `
  -RedirectStandardOutput "logs\assajda_batch2.log" `
  -RedirectStandardError "logs\assajda_batch2_err.log" `
  -PassThru

Log "Batch 2 lancé (PID: $($batch2Proc.Id)), en attente..."
Wait-Process-Done $batch2Proc.Id

Log "Batch 2 terminé"
$jsonls2 = Get-ChildItem "E:\Coran_data\train_*_assajda.jsonl" -ErrorAction SilentlyContinue
Log "Réciteurs batch 2: $($jsonls2.Count)"
Log "E: libre: $([math]::Round((Get-PSDrive E).Free/1GB, 1)) GB"

# ──────────────────────────────────────────────────────────────────────────────
# PHASE 3 : Husary Muallim JSONL (6196 WAVs déjà téléchargés)
# ──────────────────────────────────────────────────────────────────────────────
Log "PHASE 3 : Génération JSONL Husary Muallim..."
$husaryWavDir = "data\train_wav\Husary_Muallim_128kbps"
if (Test-Path $husaryWavDir) {
    $wavCount = (Get-ChildItem $husaryWavDir -Filter "*.wav" | Measure-Object).Count
    Log "WAVs Husary trouvés: $wavCount"
    .\.venv\Scripts\python -c @"
import json, re, os, sys
from pathlib import Path
sys.stdout.reconfigure(encoding='utf-8')

BASE_DIR = Path('D:/Coran Karim/benchmark')
wav_dir  = BASE_DIR / 'data/train_wav/Husary_Muallim_128kbps'

# Charge le texte du Coran
quran = {}
with open(BASE_DIR / 'data/manifest_full_wav.jsonl', encoding='utf-8') as f:
    for line in f:
        try:
            e = json.loads(line)
            if e.get('text'): quran[e.get('key','')] = e['text']
        except: pass

results = []
for wav in sorted(wav_dir.glob('*.wav')):
    m = re.match(r'(\d+)_(\d+)\.wav', wav.name)
    if not m: continue
    surah, verse = int(m.group(1)), int(m.group(2))
    key = f'{surah}:{verse}'
    text = quran.get(key, '')
    if not text: continue
    results.append({'key': key, 'reciter': 'Husary_Muallim_128kbps',
                    'text': text,
                    'wav': str(wav.relative_to(BASE_DIR)).replace('\\', '/'),
                    'duration': round(wav.stat().st_size / (16000*2), 3)})

out = BASE_DIR / 'data/train_Husary_Muallim_128kbps.jsonl'
with open(out, 'w', encoding='utf-8') as f:
    for e in sorted(results, key=lambda x: (int(x['key'].split(':')[0]), int(x['key'].split(':')[1]))):
        f.write(json.dumps(e, ensure_ascii=False) + '\n')
print(f'Husary Muallim: {len(results)} versets -> {out.name}')
"@
} else {
    Log "ATTENTION: Husary Muallim WAV dir non trouvé"
}

# ──────────────────────────────────────────────────────────────────────────────
# PHASE 4 : Manifest unifié (D: + E:)
# ──────────────────────────────────────────────────────────────────────────────
Log "PHASE 4 : Génération manifest unifié..."
.\.venv\Scripts\python -c @"
import json, sys
from pathlib import Path
sys.stdout.reconfigure(encoding='utf-8')

sources = [
    # Manifest existant (41 reciters EveryAyah)
    Path('D:/Coran Karim/benchmark/data/manifest_full_wav.jsonl'),
    # Husary Muallim
    Path('D:/Coran Karim/benchmark/data/train_Husary_Muallim_128kbps.jsonl'),
    # Omar Al-Kazabri YouTube
    Path('D:/Coran Karim/benchmark/data/train_OmarQazabri_128kbps.jsonl'),
    # Batch 1 assajda (D:)
    *list(Path('D:/Coran Karim/benchmark/data').glob('train_*_assajda.jsonl')),
    # Batch 2 assajda (E:)
    *list(Path('E:/Coran_data').glob('train_*_assajda.jsonl')),
]

all_entries = []
seen_keys = set()
for src in sources:
    if not src.exists():
        print(f'SKIP (not found): {src.name}')
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

# Stats par réciteur
from collections import Counter
reciters = Counter(e.get('reciter','?') for e in all_entries)
print(f'\n{len(reciters)} reciteurs, {len(all_entries)} versets total')
"@

# ──────────────────────────────────────────────────────────────────────────────
# PHASE 5 : Préparation NeMo FastConformer
# ──────────────────────────────────────────────────────────────────────────────
Log "PHASE 5 : Préparation données NeMo FastConformer..."
.\.venv\Scripts\python prepare_nemo_data.py --manifest "data\manifest_unified.jsonl" 2>&1 | Tee-Object -Append "logs\overnight.log"

Log "=== PIPELINE NOCTURNE TERMINÉ ==="
Log "D: libre: $([math]::Round((Get-PSDrive D).Free/1GB, 1)) GB"
Log "E: libre: $([math]::Round((Get-PSDrive E).Free/1GB, 1)) GB"
