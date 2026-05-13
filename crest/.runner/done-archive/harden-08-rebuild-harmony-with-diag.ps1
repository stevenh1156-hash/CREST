Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Rebuilding Crest.Harmony with diagnostic logging hooks..." -ForegroundColor Cyan
$ok = Build-CrestRepo -Name Harmony -Clean
if (-not $ok) { Write-Host "==> Build failed" -ForegroundColor Red; exit 1 }

# Replace just the Crest.Harmony.dll in the deployed bundle
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
$src = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll'
if (Test-Path $src) {
    Copy-Item $src -Destination $bin -Force
    Write-Host "==> Hot-swapped Crest.Harmony.dll into deployed bundle"
}

# Pre-create the log dir + clear any old log
$logDir = 'C:\dev\bannerlord\crest'
$logFile = "$logDir\runtime.log"
if (Test-Path $logFile) { Remove-Item $logFile -Force }
Write-Host ""
Write-Host "==> Ready. When you launch the game now, every assembly load,"
Write-Host "    failed resolution, and unhandled exception writes to:"
Write-Host "      $logFile"
Write-Host ""
Write-Host "    Crash, then tell me 'done' and I'll read the log."
exit 0
