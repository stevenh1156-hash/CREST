$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Rebuilding affected repos after ValidateLoadOrder neutering" -ForegroundColor Cyan

$rebuildOk = $true
foreach ($n in @('ButterLib', 'UIExtenderEx', 'MCM')) {
    Write-Host ""
    Write-Host "---- $n ----" -ForegroundColor Cyan
    $ok = Build-CrestRepo -Name $n
    if (-not $ok) {
        Write-Host "  BUILD FAILED for $n" -ForegroundColor Red
        $rebuildOk = $false
    }
}

if (-not $rebuildOk) {
    Write-Error "One or more rebuilds failed; refusing to assemble bundle."
    exit 1
}

Write-Host ""
Write-Host "==> Rebuilding bundle (skip-build, since we just built)" -ForegroundColor Cyan
$bundleOk = Build-CrestBundle -SkipBuild
if (-not $bundleOk) {
    Write-Error "Bundle assembly failed."
    exit 2
}

Write-Host ""
Write-Host "==> Deploying" -ForegroundColor Cyan
$deployOk = Deploy-CrestToBannerlord
if (-not $deployOk) {
    Write-Error "Deploy failed."
    exit 3
}

Write-Host ""
Write-Host "==> harden-14 complete - ready to launch the game" -ForegroundColor Green
