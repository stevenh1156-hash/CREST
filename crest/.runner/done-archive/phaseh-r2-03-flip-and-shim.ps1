# Phase H restart, step 3: flip internals public on built Crest.X.dll's,
# then generate the 4 compatibility shim DLLs (Bannerlord.Harmony.dll,
# Bannerlord.ButterLib.dll, Bannerlord.UIExtenderEx.dll, MCMv5.dll) using the
# pure-Cecil generator.

$ErrorActionPreference = 'Stop'

Write-Host "==> Step 1: flip-internals-public on Crest.X.dll's" -ForegroundColor Cyan
& pwsh -NoProfile -File C:\dev\bannerlord\crest\shims\flip-internals-public.ps1
if ($LASTEXITCODE -ne 0) {
    Write-Host "==> flip-internals FAILED (exit $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "==> Step 2: generate-shims (pure Cecil)" -ForegroundColor Cyan
& pwsh -NoProfile -File C:\dev\bannerlord\crest\shims\generate-shims.ps1
if ($LASTEXITCODE -ne 0) {
    Write-Host "==> generate-shims FAILED (exit $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "==> Step 3: list shim DLLs produced" -ForegroundColor Cyan
$shims = @(
    'C:\dev\bannerlord\crest\shims\Bannerlord.Harmony.Shim\Bannerlord.Harmony.dll',
    'C:\dev\bannerlord\crest\shims\Bannerlord.ButterLib.Shim\Bannerlord.ButterLib.dll',
    'C:\dev\bannerlord\crest\shims\Bannerlord.UIExtenderEx.Shim\Bannerlord.UIExtenderEx.dll',
    'C:\dev\bannerlord\crest\shims\MCMv5.Shim\MCMv5.dll'
)
$missing = $false
foreach ($s in $shims) {
    if (Test-Path $s) {
        $f = Get-Item $s
        Write-Host ("  {0,9:N1}KB  {1}" -f ($f.Length/1KB), $f.FullName) -ForegroundColor Green
    } else {
        Write-Host "  MISSING: $s" -ForegroundColor Red
        $missing = $true
    }
}
if ($missing) {
    Write-Host "==> One or more shims missing." -ForegroundColor Red
    exit 2
}
Write-Host "==> Phase H step 3 OK." -ForegroundColor Green
