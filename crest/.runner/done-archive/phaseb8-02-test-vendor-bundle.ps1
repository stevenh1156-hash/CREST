$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Re-bundle (vendor-based) and deploy" -ForegroundColor Cyan
$ok = Build-CrestBundle -SkipBuild -Version '1.0.0'
if (-not $ok) { exit 1 }
$ok = Deploy-CrestToBannerlord
if (-not $ok) { exit 2 }

# Diff: what's in the deployed bin?
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
$count = (Get-ChildItem $bin -File | Measure-Object).Count
Write-Host ""
Write-Host ("==> Deployed bin: $count files") -ForegroundColor Cyan
$total = 0
Get-ChildItem $bin -File | Sort-Object Name | ForEach-Object {
    Write-Host ("    {0,9:N0}B  {1}" -f $_.Length, $_.Name)
    $total += $_.Length
}
Write-Host ("    TOTAL: {0:N1} MB" -f ($total/1MB))
