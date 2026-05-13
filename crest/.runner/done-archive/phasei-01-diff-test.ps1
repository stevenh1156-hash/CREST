$ErrorActionPreference = 'Continue'

Write-Host '==> Extract CREST-v1.3.0 and CREST-v1.3.1 to temp dirs for comparison' -ForegroundColor Cyan
$tmp = 'C:\dev\bannerlord\crest\dist\diff-tmp'
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
New-Item -ItemType Directory -Path $tmp | Out-Null

$oldZip = 'C:\dev\bannerlord\crest\dist\CREST-v1.3.0.zip'
$newZip = 'C:\dev\bannerlord\crest\dist\CREST-v1.3.1.zip'

$oldExtract = Join-Path $tmp 'v1.3.0'
$newExtract = Join-Path $tmp 'v1.3.1'
Expand-Archive -Path $oldZip -DestinationPath $oldExtract -Force
Expand-Archive -Path $newZip -DestinationPath $newExtract -Force

# Find the bin folder inside each (zip layout has Modules\CREST\bin\Win64_Shipping_Client\)
$oldBin = Join-Path $oldExtract 'Modules\CREST\bin\Win64_Shipping_Client'
$newBin = Join-Path $newExtract 'Modules\CREST\bin\Win64_Shipping_Client'

if (-not (Test-Path $oldBin)) { Write-Host "MISS old bin: $oldBin" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $newBin)) { Write-Host "MISS new bin: $newBin" -ForegroundColor Red; exit 1 }

Write-Host ''
Write-Host '==> Run Compare-CrestVersions.ps1 (no mod-scan)' -ForegroundColor Cyan
$reportPath = Join-Path $tmp 'diff-v1.3.0-to-v1.3.1.md'
& 'C:\dev\bannerlord\crest\tools\diff\Compare-CrestVersions.ps1' `
    -OldDir $oldBin -NewDir $newBin -ReportPath $reportPath

Write-Host ''
Write-Host '==> Run again WITH mod-scan against installed game Modules' -ForegroundColor Cyan
$gameModules = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules'
$reportPath2 = Join-Path $tmp 'diff-v1.3.0-to-v1.3.1-with-mods.md'
& 'C:\dev\bannerlord\crest\tools\diff\Compare-CrestVersions.ps1' `
    -OldDir $oldBin -NewDir $newBin `
    -ScanMods $gameModules `
    -ReportPath $reportPath2

Write-Host ''
Write-Host ('==> Reports:') -ForegroundColor Green
Write-Host ('   ' + $reportPath)
Write-Host ('   ' + $reportPath2)
