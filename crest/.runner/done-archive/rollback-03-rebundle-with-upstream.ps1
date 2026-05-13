$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

# Verify upstream BUTR folders are present
$blUpstream = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\Bannerlord.ButterLib\bin\Win64_Shipping_Client'
if (Test-Path $blUpstream) {
    Write-Host "==> Upstream Bannerlord.ButterLib install detected - bundle will source third-party deps from there" -ForegroundColor Green
    Write-Host ("    {0} files in upstream BUTR bin" -f (Get-ChildItem $blUpstream -File | Measure-Object).Count)
} else {
    Write-Host "==> Upstream Bannerlord.ButterLib install NOT found - falling back to NuGet cache" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==> Re-bundle (SkipBuild)" -ForegroundColor Cyan
$ok = Build-CrestBundle -SkipBuild -Version '1.0.0'
if (-not $ok) { exit 1 }

Write-Host ""
Write-Host "==> Deploy" -ForegroundColor Cyan
$ok = Deploy-CrestToBannerlord
if (-not $ok) { exit 2 }

# Diff what's deployed now vs. what we had
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
Write-Host ""
Write-Host "==> Final deployed bin:" -ForegroundColor Cyan
$count = (Get-ChildItem $bin -File | Measure-Object).Count
Write-Host "    $count files"
Get-ChildItem $bin -File | Sort-Object Name | ForEach-Object {
    Write-Host ("    {0,9:N0}B  {1}" -f $_.Length, $_.Name)
}
