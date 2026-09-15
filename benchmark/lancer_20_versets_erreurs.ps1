param([string]$Serial = 'R3CY20XW7TD')
$ErrorActionPreference = 'Stop'
$adbPath = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
$folder = Join-Path $PSScriptRoot 'replay_20_versets_erreurs'
$package = 'com.corankarim.coran_karim.dev'
$remote = "/sdcard/Android/data/$package/files/replay_20_erreurs.wav"
$journal = "/sdcard/Android/data/$package/files/recitation_diagnostic.log"
$marker = 'REPLAY20-' + [guid]::NewGuid().ToString('N')
& $adbPath -s $Serial push (Join-Path $folder '20_versets_erreurs.wav') $remote
if ($LASTEXITCODE -ne 0) { throw 'Transfert impossible' }
& $adbPath -s $Serial shell "echo $marker >> $journal"
& $adbPath -s $Serial shell input keyevent KEYCODE_WAKEUP
& $adbPath -s $Serial shell wm dismiss-keyguard
& $adbPath -s $Serial shell am force-stop $package
& $adbPath -s $Serial shell am start -n "$package/com.corankarim.coran_karim.MainActivity" --es recette ecoute --ez normal true --ei sourate 78 --ei depart 1 --ei versets 20 --es wav $remote --es riwaya hafs
if ($LASTEXITCODE -ne 0) { throw 'Lancement impossible' }
$deadline = (Get-Date).AddMinutes(4)
$logPath = Join-Path $folder ('execution_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
do {
    Start-Sleep -Seconds 5
    $raw = (& $adbPath -s $Serial shell cat $journal) -join "`n"
    $offset = $raw.LastIndexOf($marker)
    $session = if ($offset -ge 0) { $raw.Substring($offset) } else { '' }
    Set-Content -LiteralPath $logPath -Value $session -Encoding utf8
    $ended = $session.Contains('SOURCE DETERMINISTE : fin du fichier')
} while (-not $ended -and (Get-Date) -lt $deadline)
Write-Host "Fin audio=$ended. Journal : $logPath. Ecran laisse ouvert."
