Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Rebuilding Crest.Harmony with Environment.StackTrace logging..." -ForegroundColor Cyan
$ok = Build-CrestRepo -Name Harmony -Clean
if (-not $ok) { exit 1 }

# Hot-swap into deployed bundle (we know auto-deploy is partially disabled now)
$src = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll'
$dst = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client\Crest.Harmony.dll'
$staging = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client\Crest.Harmony.dll'
Copy-Item $src -Destination $dst -Force
Copy-Item $src -Destination $staging -Force
Write-Host "    hot-swapped into both staging and deployed"

$logFile = 'C:\dev\bannerlord\crest\runtime.log'
if (Test-Path $logFile) { Remove-Item $logFile -Force }

# Verify deployed SubModule.xml is still our 3-entry version (auto-deploy didn't strike)
$smPath = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\SubModule.xml'
if (Test-Path $smPath) {
    $sm = Get-Content $smPath -Raw
    if ($sm -match 'Crest.Harmony.dll') {
        Write-Host "==> Deployed SubModule.xml still references Crest.Harmony.dll (good)" -ForegroundColor Green
    } else {
        Write-Host "==> Deployed SubModule.xml was overwritten - redeploying full bundle..." -ForegroundColor Yellow
        Deploy-CrestToBannerlord | Out-Null
    }
}

Write-Host ""
Write-Host "==> Try launching. The next first-chance exception will include the full"
Write-Host "    call stack so we can see WHO called GetRequiredService(null)."
exit 0
