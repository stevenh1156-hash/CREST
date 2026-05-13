# Phase D.2: Rebuild bundle with tightened allowlist + new 9-entry SubModule.xml
$ErrorActionPreference = 'Stop'

Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Phase D.2 rebuild starting" -ForegroundColor Cyan

# Build with -SkipBuild because all repos were already compiled in the previous session.
# We're only re-staging the bundle layout, not rebuilding code.
$ok = Build-CrestBundle -SkipBuild
if (-not $ok) {
    Write-Error "Bundle assembly failed."
    exit 1
}

Write-Host ""
Write-Host "==> Verifying bundle contents" -ForegroundColor Cyan
$binDir = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client'

# Confirm the two dropped DLLs are gone.
$shouldNotExist = @('Bannerlord.ModuleLoader.CREST.dll', 'System.Reflection.Metadata.dll')
$failed = $false
foreach ($n in $shouldNotExist) {
    if (Test-Path (Join-Path $binDir $n)) {
        Write-Host "  [FAIL] $n still in bundle" -ForegroundColor Red
        $failed = $true
    } else {
        Write-Host "  [OK] $n correctly absent" -ForegroundColor Green
    }
}

# Confirm the kept DLLs are still there.
$shouldExist = @(
    'Crest.Harmony.dll', 'Crest.ButterLib.dll', 'Crest.ButterLib.Implementation.dll',
    'Crest.UIExtenderEx.dll', 'Crest.MCM.dll', 'Crest.MCM.UI.Adapter.MCMv5.dll',
    'CREST.v1.4.1.dll', 'BetterExceptionWindow.dll', 'BetterExceptionWindowConfigUI.dll',
    'DotNetZip.dll', '0Harmony.dll'
)
foreach ($n in $shouldExist) {
    if (-not (Test-Path (Join-Path $binDir $n))) {
        Write-Host "  [FAIL] $n missing from bundle" -ForegroundColor Red
        $failed = $true
    }
}
if (-not $failed) {
    Write-Host "  [OK] all expected entry-point DLLs present" -ForegroundColor Green
}

# Verify SubModule.xml has the 9 expected entries.
$smx = Get-Content (Join-Path 'C:\dev\bannerlord\crest\dist\CREST' 'SubModule.xml') -Raw
$count = ([regex]::Matches($smx, '<SubModule>')).Count
Write-Host ("  SubModule entries: $count (expected 9)") -ForegroundColor $(if ($count -eq 9) { 'Green' } else { 'Red' })
if ($count -ne 9) { $failed = $true }

# List final bin folder size
$totalKb = (Get-ChildItem $binDir -File | Measure-Object -Property Length -Sum).Sum / 1KB
Write-Host ("  bin folder total: {0:N1} KB across $((Get-ChildItem $binDir -File).Count) files" -f $totalKb)

if ($failed) {
    Write-Error "Verification failed."
    exit 2
}

Write-Host ""
Write-Host "==> Deploying to game folder" -ForegroundColor Cyan
$deployed = Deploy-CrestToBannerlord
if (-not $deployed) {
    Write-Error "Deploy failed."
    exit 3
}

Write-Host ""
Write-Host "==> Phase D.2 complete - ready to launch the game" -ForegroundColor Green
