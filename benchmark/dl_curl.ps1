$ErrorActionPreference = "Continue"
$token = $env:HF_TOKEN
$base  = "D:\Coran Karim\benchmark\models"
$files = @("config.json","generation_config.json","chat_template.jinja",
           "processor_config.json","tokenizer_config.json","tokenizer.json","model.safetensors")
$repos = @("google/gemma-4-E2B-it","google/gemma-4-E4B-it")

foreach ($repo in $repos) {
    $name = $repo.Split("/")[-1]
    $dir = Join-Path $base $name
    New-Item -ItemType Directory -Force $dir | Out-Null
    foreach ($f in $files) {
        $url = "https://huggingface.co/$repo/resolve/main/$f"
        $out = Join-Path $dir $f
        Write-Output "DL $name/$f"
        for ($try=1; $try -le 40; $try++) {
            # -C - resume; --speed-time aborts a stalled connection so --retry can resume
            curl.exe -L -s --fail -C - --ssl-no-revoke -4 `
                -H "Authorization: Bearer $token" `
                --retry 40 --retry-all-errors --retry-delay 3 `
                --speed-limit 30000 --speed-time 20 `
                -o "$out" "$url"
            if ($LASTEXITCODE -eq 0) { Write-Output "  OK $f"; break }
            Write-Output "  retry $try (curl exit $LASTEXITCODE)"
            Start-Sleep -Seconds 2
        }
    }
    Write-Output "[$name] DONE"
}
Write-Output "ALL DONE"
