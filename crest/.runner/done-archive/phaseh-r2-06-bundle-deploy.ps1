# Phase H restart, step 4 (retry without em-dash): bundle + deploy.
$ErrorActionPreference = 'Stop'

Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Build-CrestBundle -SkipBuild (DLLs already fresh)" -ForegroundColor Cyan
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
Write-Host "==> Final bin contents at deployment target" -ForegroundColor Cyan
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
Get-ChildItem $bin | Sort-Object Name | ForEach-Object {
    $kb = [math]::Round($_.Length / 1KB, 1)
    Write-Host ("  {0,9}KB  {1}" -f $kb, $_.Name)
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
