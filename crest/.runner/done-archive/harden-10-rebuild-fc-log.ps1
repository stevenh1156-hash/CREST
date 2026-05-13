Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Rebuilding Crest.Harmony with full first-chance exception logging..." -ForegroundColor Cyan
$ok = Build-CrestRepo -Name Harmony -Clean
if (-not $ok) { exit 1 }

# Hot-swap into deployed bundle (bundle staging is correct, just need new Harmony.dll)
$src = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll'
$dst = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client\Crest.Harmony.dll'
Copy-Item $src -Destination $dst -Force

# Also update the staging copy
Copy-Item $src -Destination 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client\Crest.Harmony.dll' -Force

# Clear old log
$logFile = 'C:\dev\bannerlord\crest\runtime.log'
if (Test-Path $logFile) { Remove-Item $logFile -Force }

Write-Host ""
Write-Host "==> Hot-swapped diagnostic Crest.Harmony.dll. Try launching."
Write-Host "    This time every first-chance exception writes to runtime.log,"
Write-Host "    including the one TaleWorlds was catching before."
exit 0
