param(
    [string]$CaseId = 'H-001',
    [string]$Serial = 'R3CY20XW7TD',
    [string]$Package = 'com.corankarim.coran_karim.dev'
)

# Un cas a la fois : laisser l'ecran ouvert pour observer les verdicts.
$ErrorActionPreference = 'Stop'
$rootPath = Split-Path $PSScriptRoot -Parent
$campaignPath = Join-Path $PSScriptRoot 'campagne_hafs_qf_2026-09-13'
$adbPath = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
$case = Get-Content (Join-Path $campaignPath 'manifest_cases.jsonl') -Encoding utf8 |
    ForEach-Object { if ($_.Trim()) { $_ | ConvertFrom-Json } } |
    Where-Object case_id -eq $CaseId
if (-not $case) { throw "Cas inconnu : $CaseId" }
$wavPath = Join-Path $rootPath $case.wav_final
if (-not (Test-Path -LiteralPath $wavPath)) { throw "WAV absent : $wavPath" }
$remotePath = "/sdcard/Android/data/$Package/files/recette_source.wav"
$parts = $case.versets -split ':'
& $adbPath -s $Serial get-state
if ($LASTEXITCODE -ne 0) { throw 'Telephone indisponible' }
& $adbPath -s $Serial push $wavPath $remotePath
if ($LASTEXITCODE -ne 0) { throw 'Transfert WAV impossible' }
& $adbPath -s $Serial shell input keyevent KEYCODE_WAKEUP
& $adbPath -s $Serial shell wm dismiss-keyguard
& $adbPath -s $Serial shell am force-stop $Package
& $adbPath -s $Serial shell am start -n "$Package/com.corankarim.coran_karim.MainActivity" --es recette ecoute --ez normal true --ez borner true --ei sourate $parts[0] --ei depart $parts[1] --ei versets 1 --es wav $remotePath --es riwaya hafs
if ($LASTEXITCODE -ne 0) { throw 'Lancement impossible' }
Write-Host "$CaseId ($($case.famille)) : replay temps reel, mode normal. Ecran laisse ouvert."
