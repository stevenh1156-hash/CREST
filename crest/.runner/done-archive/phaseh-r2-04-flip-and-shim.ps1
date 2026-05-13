# Phase H restart, step 3 (retry without pwsh): just dot-source the scripts.
$ErrorActionPreference = 'Stop'

Write-Host "==> Step 1: flip-internals-public on Crest.X.dll's" -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\shims\flip-internals-public.ps1'

Write-Host ""
Write-Host "==> Step 2: generate-shims (pure Cecil)" -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\shims\generate-shims.ps1'

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
if ($missing) { exit 2 }
Write-Host "==> Phase H step 3 OK." -ForegroundColor Green
