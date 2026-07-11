# Script de lancement Flutter — contourne l'inspection SSL de Norton
# Usage:
#   .\flutter_run.ps1          -> run sur device/emulateur connecte
#   .\flutter_run.ps1 build    -> genere app-debug.apk
#   .\flutter_run.ps1 release  -> genere app-release.apk (signe)
#   .\flutter_run.ps1 install  -> build + install sur device ADB
$env:JAVA_TOOL_OPTIONS = "-Djavax.net.ssl.trustStore=D:/gradle-cacerts.jks -Djavax.net.ssl.trustStorePassword=changeit"
$ADB = "C:\Users\Adam\AppData\Local\Android\Sdk\platform-tools\adb.exe"
Set-Location $PSScriptRoot

switch ($args[0]) {
    "build"   { flutter build apk --debug }
    "release" { flutter build apk --release }
    "install" {
        flutter build apk --debug
        if ($LASTEXITCODE -eq 0) {
            & $ADB install -r "build\app\outputs\flutter-apk\app-debug.apk"
        }
    }
    default   { flutter run }
}
