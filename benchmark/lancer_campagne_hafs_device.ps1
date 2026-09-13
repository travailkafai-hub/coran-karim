param(
    [string]$Serial = 'R3CY20XW7TD',
    [string]$Package = 'com.corankarim.coran_karim.dev',
    [string]$Campaign = "$PSScriptRoot\campagne_hafs_qf_2026-09-13",
    [int]$TimeoutSeconds = 120
)

# adb writes normal progress messages (notably `push`) to stderr even when its
# exit code is zero. We inspect exit codes explicitly instead of treating that
# stream as a terminating PowerShell exception.
$ErrorActionPreference = 'Continue'
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb)) {
    throw "adb introuvable: $adb"
}

$manifestPath = Join-Path $Campaign 'manifest_cases.jsonl'
$replayPath = Join-Path $Campaign 'replays.json'
$logsPath = Join-Path $Campaign 'device_logs'
$resultsPath = Join-Path $Campaign 'executions.jsonl'
$remoteWav = "/sdcard/Android/data/$Package/files/recette_source.wav"
$remoteLog = "/sdcard/Android/data/$Package/files/recitation_diagnostic.log"

if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Manifeste introuvable: $manifestPath"
}
New-Item -ItemType Directory -Force -Path $logsPath | Out-Null
Set-Content -LiteralPath $resultsPath -Value '' -Encoding utf8

function Invoke-Device {
    param([string[]]$Arguments)
    & $adb -s $Serial @Arguments 2>&1 | Out-String
}

function Get-LogLineCount {
    $raw = Invoke-Device @('shell', "wc -l < $remoteLog")
    $match = [regex]::Match($raw, '\d+')
    if (-not $match.Success) { return 0 }
    return [int]$match.Value
}

function Get-LogTail {
    param([int]$Lines = 160)
    return Invoke-Device @('shell', "tail -n $Lines $remoteLog")
}

function Get-SessionLog {
    param([int]$Before)
    $now = Get-LogLineCount
    $from = if ($now -lt $Before) { 1 } else { $Before + 1 }
    return Invoke-Device @('shell', "tail -n +$from $remoteLog")
}

function Write-Result {
    param([hashtable]$Value)
    ($Value | ConvertTo-Json -Compress -Depth 8) | Add-Content -LiteralPath $resultsPath -Encoding utf8
}

function First-Match {
    param([string]$Text, [string]$Pattern)
    $m = [regex]::Match($Text, $Pattern)
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

$devices = Invoke-Device @('get-state')
if ($devices -notmatch 'device') {
    throw "Appareil indisponible: $Serial ($devices)"
}

$cases = @(Get-Content -LiteralPath $manifestPath -Encoding utf8 | ForEach-Object {
    if ($_.Trim()) { $_ | ConvertFrom-Json }
})
$replays = Get-Content -LiteralPath $replayPath -Raw -Encoding utf8 | ConvertFrom-Json
$replayIds = @{}
foreach ($entry in $replays.cases) {
    $replayIds[$entry.case_id] = @(1, 2, 3)
}

Write-Host "Campagne Hafs sur $Serial ($($cases.Count) cas distincts)"
$number = 0
foreach ($case in $cases) {
    $runs = if ($replayIds.ContainsKey($case.case_id)) {
        $replayIds[$case.case_id]
    } else {
        @(1)
    }
    foreach ($run in $runs) {
        $number++
        $wav = Join-Path (Get-Location) $case.wav_final
        if (-not (Test-Path -LiteralPath $wav)) {
            throw "WAV introuvable pour $($case.case_id): $wav"
        }
        $parts = $case.versets -split ':'
        $surah = [int]$parts[0]
        $ayah = [int]$parts[1]
        $before = Get-LogLineCount
        $startedAt = Get-Date
        $status = 'TIMEOUT'
        $tail = ''

        Invoke-Device @('shell', 'am', 'force-stop', $Package) | Out-Null
        $push = Invoke-Device @('push', $wav, $remoteWav)
        if ($LASTEXITCODE -ne 0) {
            $status = 'PUSH_FAILED'
        } else {
            Invoke-Device @(
                'shell', 'am', 'start', '-n', "$Package/com.corankarim.coran_karim.MainActivity",
                '--es', 'recette', 'v2',
                '--ei', 'sourate', "$surah",
                '--ei', 'depart', "$ayah",
                '--ei', 'versets', '1',
                '--es', 'wav', $remoteWav,
                '--es', 'riwaya', 'hafs'
            ) | Out-Null

            for ($second = 0; $second -lt $TimeoutSeconds; $second++) {
                Start-Sleep -Seconds 1
                # Read only the lines added after this run. This avoids both
                # old FIN DU BANC markers and PowerShell code-page issues on
                # the accented session-start marker.
                $tail = Get-SessionLog $before
                if ($tail -match 'FIN DU BANC') {
                    $status = 'DONE'
                    break
                }
            }
        }

        $sessionLog = Get-SessionLog $before
        $logFile = Join-Path $logsPath "$($case.case_id)-r$run.log"
        Set-Content -LiteralPath $logFile -Value $sessionLog -Encoding utf8
        $nonGreen = [regex]::Match($sessionLog, 'non verts\s*:\s*(\d+)\s*/\s*(\d+)')
        $locked = [regex]::Match($sessionLog, 'TAUX VERROUILLE\s*:\s*(\d+)\s*/\s*(\d+)')
        $build = First-Match $sessionLog 'BUILD code=([^\r\n]+)'
        $result = @{
            case_id = $case.case_id
            run = [int]$run
            distinct_case = $true
            riwaya = 'Hafs'
            famille = $case.famille
            split = $case.split
            sourate = $surah
            ayah = $ayah
            recitateur = $case.recitateur
            status = $status
            build = $build
            non_verts = if ($nonGreen.Success) { [int]$nonGreen.Groups[1].Value } else { $null }
            mots = if ($nonGreen.Success) { [int]$nonGreen.Groups[2].Value } else { $null }
            verrouilles = if ($locked.Success) { [int]$locked.Groups[1].Value } else { $null }
            log = (Resolve-Path $logFile).Path
            started_at = $startedAt.ToString('o')
            finished_at = (Get-Date).ToString('o')
        }
        Write-Result $result
        Write-Host ("[{0}/{1}] {2} run={3} status={4} non_verts={5}/{6}" -f `
            $number, 80, $case.case_id, $run, $status, $result.non_verts, $result.mots)
    }
}

Write-Host "Campagne terminee. Resultats: $resultsPath"
