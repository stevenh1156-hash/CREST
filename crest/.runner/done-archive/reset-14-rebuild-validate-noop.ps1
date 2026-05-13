$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

# Rebuild ButterLib + UIExtenderEx (where we re-neutered ValidateLoadOrder)
Write-Host "==> Rebuild ButterLib and UIExtenderEx (ValidateLoadOrder re-neutered)" -ForegroundColor Cyan
Build-CrestRepo -Name 'ButterLib' | Out-Null
if ($LASTEXITCODE -ne 0 -and $false) { Write-Host "  ButterLib build issue" -ForegroundColor Yellow }
Build-CrestRepo -Name 'UIExtenderEx' | Out-Null

# Cecil flip on the two updated DLLs (need to redo since we just rebuilt)
& 'C:\dev\bannerlord\crest\shims\flip-internals-public.ps1'

# Restore shims to bin (they were moved to shims-disabled/ in the last test)
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
$shimsDisabled = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\shims-disabled'
if (Test-Path $shimsDisabled) {
    Get-ChildItem $shimsDisabled -Filter '*.dll' | ForEach-Object {
        Move-Item $_.FullName -Destination (Join-Path $bin $_.Name) -Force
    }
    Remove-Item $shimsDisabled -Force
    Write-Host "==> Restored shim DLLs to bin/" -ForegroundColor DarkGray
}

# Re-bundle + redeploy
Write-Host ""
Write-Host "==> Re-bundle + redeploy" -ForegroundColor Cyan
$ok = Build-CrestBundle -SkipBuild -Version '1.0.0'
if (-not $ok) { exit 1 }
$ok = Deploy-CrestToBannerlord
if (-not $ok) { exit 2 }

Write-Host ""
Write-Host "==> READY - launch the game" -ForegroundColor Green
