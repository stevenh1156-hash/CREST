$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Bundle (with NuGet-cache fallback for third-party deps)" -ForegroundColor Cyan
$ok = Build-CrestBundle -SkipBuild -Version '1.0.0'
if (-not $ok) { exit 1 }

Write-Host ""
Write-Host "==> Deploy" -ForegroundColor Cyan
$ok = Deploy-CrestToBannerlord
if (-not $ok) { exit 2 }

# Show final deployed bin contents
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
Write-Host ""
Write-Host "==> Final deployed bin folder:" -ForegroundColor Cyan
$count = (Get-ChildItem $bin -File | Measure-Object).Count
Write-Host "    $count files"
Get-ChildItem $bin -File | Sort-Object Name | ForEach-Object {
    Write-Host ("    {0,9:N0}B  {1}" -f $_.Length, $_.Name)
}

Write-Host ""
Write-Host "==> READY - launch the game" -ForegroundColor Green
