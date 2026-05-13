# Phase H restart, step 2: build all 4 forks (no namespace check; we know it's correct).
$ErrorActionPreference = 'Stop'

Write-Host "==> Build-AllCrestRepos -Clean" -ForegroundColor Cyan
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force
$ok = Build-AllCrestRepos -Clean
if (-not $ok) {
    Write-Host "==> BUILD FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "==> BUILD OK" -ForegroundColor Green

Write-Host ""
Write-Host "==> Produced DLLs:" -ForegroundColor Cyan
$outputs = @(
    'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll',
    'C:\dev\bannerlord\Bannerlord.ButterLib\src\Crest.ButterLib\bin\Release\net472\Crest.ButterLib.dll',
    'C:\dev\bannerlord\Bannerlord.ButterLib\src\Crest.ButterLib.Implementation\bin\Stable_Release\net472\Crest.ButterLib.Implementation.dll',
    'C:\dev\bannerlord\Bannerlord.UIExtenderEx\src\Crest.UIExtenderEx\bin\Release\netstandard2.0\Crest.UIExtenderEx.dll',
    'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src\Crest.MCM\bin\Release\netstandard2.0\Crest.MCM.dll',
    'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI\bin\Stable_Release\netstandard2.0\Crest.MCM.UI.dll'
)
foreach ($o in $outputs) {
    if (Test-Path $o) {
        $f = Get-Item $o
        Write-Host ("  {0,9:N1}KB  {1}" -f ($f.Length/1KB), $f.FullName) -ForegroundColor Green
    } else {
        Write-Host "  MISSING: $o" -ForegroundColor Red
    }
}
