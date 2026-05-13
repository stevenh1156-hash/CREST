# Phase H restart, step 4: assemble bundle (includes shim DLLs via Layer 5c)
# and deploy into Modules\CREST\.

$ErrorActionPreference = 'Stop'

Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Build-CrestBundle (skip rebuild — DLLs are fresh)" -ForegroundColor Cyan
$ok = Build-CrestBundle -Version '1.1.0' -SkipBuild
if (-not $ok) {
    Write-Host "==> Bundle FAILED" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "==> Deploy-CrestToBannerlord" -ForegroundColor Cyan
$ok = Deploy-CrestToBannerlord
if (-not $ok) {
    Write-Host "==> Deploy FAILED" -ForegroundColor Red
    exit 2
}

Write-Host ""
Write-Host "==> Final bin\ contents at deployment target" -ForegroundColor Cyan
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
Get-ChildItem $bin | Sort-Object Name | ForEach-Object {
    Write-Host ("  {0,9:N1}KB  {1}" -f ($_.Length/1KB), $_.Name)
}

Write-Host ""
Write-Host "==> Verify shim DLLs are present in deployment" -ForegroundColor Cyan
$expected = @('Bannerlord.Harmony.dll','Bannerlord.ButterLib.dll','Bannerlord.UIExtenderEx.dll','MCMv5.dll')
foreach ($name in $expected) {
    $p = Join-Path $bin $name
    if (Test-Path $p) {
        Write-Host "  OK   $name" -ForegroundColor Green
    } else {
        Write-Host "  MISS $name" -ForegroundColor Red
    }
}
