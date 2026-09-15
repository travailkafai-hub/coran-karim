param(
    [string]$Serial = 'R3CY20XW7TD',
    [string]$Package = 'com.corankarim.coran_karim.dev',
    [int]$ObservationSeconds = 10,
    [switch]$ErrorsOnly,
    [switch]$NoReplays
)
$ErrorActionPreference = 'Stop'
$campaignPath = Join-Path $PSScriptRoot 'campagne_hafs_qf_2026-09-13'
$outputPath = Join-Path $campaignPath ('app_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $outputPath | Out-Null
$adbPath = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
$remoteLog = "/sdcard/Android/data/$Package/files/recitation_diagnostic.log"
$cases = @(Get-Content (Join-Path $campaignPath 'manifest_cases.jsonl') -Encoding utf8 |
    ForEach-Object { if ($_.Trim()) { $_ | ConvertFrom-Json } })
$replays = Get-Content (Join-Path $campaignPath 'replays.json') -Raw | ConvertFrom-Json
if ($ErrorsOnly) {
    $cases = @($cases | Where-Object { $_.famille -in @('omission', 'substitution', 'insertion', 'permutation', 'truncation') })
}
$total = 0
foreach ($entry in $cases) {
    $total += $(if (-not $NoReplays -and $entry.case_id -in $replays.cases.case_id) { 3 } else { 1 })
}
$number = 0
Write-Host "Resultats et logs : $outputPath"
foreach ($case in $cases) {
    $runs = if (-not $NoReplays -and $case.case_id -in $replays.cases.case_id) { 3 } else { 1 }
    for ($run = 1; $run -le $runs; $run++) {
        $number++
        # A unique marker excludes all earlier sessions without clearing logs.
        $marker = 'APP-REPLAY-' + [guid]::NewGuid().ToString('N')
        & $adbPath -s $Serial shell "echo $marker >> $remoteLog"
        if ($LASTEXITCODE -ne 0) { throw 'Journal inaccessible' }
        $startedAt = Get-Date
        & (Join-Path $PSScriptRoot 'lancer_cas_hafs_app.ps1') -CaseId $case.case_id -Serial $Serial -Package $Package
        $deadline = (Get-Date).AddSeconds(120 + $case.audio_duration_ms / 1000)
        $eof = $false
        do {
            Start-Sleep -Seconds 2
            $raw = (& $adbPath -s $Serial shell cat $remoteLog) -join "`n"
            if ($LASTEXITCODE -ne 0) { throw 'Connexion telephone perdue' }
            $offset = $raw.LastIndexOf($marker)
            $session = if ($offset -ge 0) { $raw.Substring($offset) } else { '' }
            $eof = $session.Contains('SOURCE DETERMINISTE : fin du fichier')
        } while (-not $eof -and (Get-Date) -lt $deadline)
        if ($eof) { Start-Sleep -Seconds $ObservationSeconds }
        $raw = (& $adbPath -s $Serial shell cat $remoteLog) -join "`n"
        $offset = $raw.LastIndexOf($marker)
        $session = if ($offset -ge 0) { $raw.Substring($offset) } else { '' }
        $logPath = Join-Path $outputPath "$($case.case_id)-r$run.log"
        Set-Content -LiteralPath $logPath -Value $session -Encoding utf8
        $status = if ($eof) { 'AUDIO_FINISHED' } else { 'TIMEOUT' }
        # EOF confirms replay only; it is not a score or a closed app session.
        @{case_id=$case.case_id; run=$run; famille=$case.famille; mode='ecoute_normal'; status=$status;
          started_at=$startedAt.ToString('o'); finished_at=(Get-Date).ToString('o'); log=$logPath} |
            ConvertTo-Json -Compress | Add-Content (Join-Path $outputPath 'executions.jsonl') -Encoding utf8
        Write-Host "[$number/$total] $($case.case_id) run=$run $status"
        if (-not $eof) { throw 'Replay non termine : campagne arretee, voir le log.' }
    }
}
Write-Host 'Campagne terminee. Dernier ecran laisse ouvert.'
