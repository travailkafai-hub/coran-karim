# Batch 2 : 26 réciteurs restants sur assajda.com -> stockés sur E:
# Lancer APRES que le batch 1 soit terminé (ou échoué)
# Usage: .\launch_batch2_assajda.ps1

$env:PYTHONIOENCODING = "utf-8"
Set-Location "D:\Coran Karim\benchmark"

# Inclut aussi les réciteurs du batch 1 qui n'ont pas eu le temps de finir sur D:
# (IdrissAbkar, KhalidAlJalil, AlzainMohamedAhmed, AdelKalbani si pas complets)
$reciters = "IdrissAbkar,KhalidAlJalil,AlzainMohamedAhmed,AdelKalbani," +
            "MohamedKantaoui,MohamedHamdan,YoussefEdghouch,NurdinMaghriby,RachidIfrad," +
            "MohamedAlJabery,AbdelhamidHssain,AbdelKabirHadidi,SamirBelaachya,MohamedElIraoui," +
            "MohamedChahboun,RachidBelaachya,FaysalWizar,AbdurrahimNabulsi,HosseinBousseksso," +
            "AbdallahMatroud,AbdulRashidSufi,AbdulWadudHaneef,AhmedSaoud,MohamedElBarak," +
            "MohamedAlMohisni,MustaphaLahouni,AntarMuslim,SaberAbdulHakam,HassanSaleh,AbdallahKamel"

Write-Output "Lancement batch 2 : 30 réciteurs -> E:\Coran_data"
Write-Output "Espace disque :"
Get-PSDrive D | Select-Object @{N='D_Free(GB)';E={[math]::Round($_.Free/1GB,1)}}
Get-PSDrive E | Select-Object @{N='E_Free(GB)';E={[math]::Round($_.Free/1GB,1)}}

New-Item -ItemType Directory -Path "E:\Coran_data" -Force | Out-Null

Start-Process -NoNewWindow -FilePath ".\.venv\Scripts\python" `
  -ArgumentList "download_assajda.py","--reciter",$reciters,"--data-dir","E:\Coran_data" `
  -RedirectStandardOutput "logs\assajda_batch2.log" `
  -RedirectStandardError "logs\assajda_batch2_err.log"

Write-Output "Lancé ! Log : logs\assajda_batch2.log"
Write-Output "Données sur : E:\Coran_data\train_wav\ et E:\Coran_data\train\"
