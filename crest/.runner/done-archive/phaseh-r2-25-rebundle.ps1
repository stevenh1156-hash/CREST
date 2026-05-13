$ErrorActionPreference = 'Stop'

Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Build-CrestBundle -SkipBuild (DLLs are already fresh)" -ForegroundColor Cyan
$ok = Build-CrestBundle -Version '1.1.0' -SkipBuild
if (-not $ok) { exit 1 }

Write-Host ""
Write-Host "==> Deploy-CrestToBannerlord" -ForegroundColor Cyan
$ok = Deploy-CrestToBannerlord
if (-not $ok) { exit 2 }

Write-Host ""
Write-Host "==> Re-render SubModule.xml from full template" -ForegroundColor Cyan
$tmpl = Get-Content 'C:\dev\bannerlord\crest\Modules\CREST\SubModule.xml.template' -Raw
$tmpl = $tmpl -replace '\$version\$', '1.1.0'
$dst = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\SubModule.xml'
Set-Content -Path $dst -Value $tmpl -Encoding UTF8

Write-Host ""
Write-Host "==> Verify all required DLLs present" -ForegroundColor Cyan
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
$musts = @(
    'Crest.Harmony.dll', 'Crest.ButterLib.dll', 'Crest.ButterLib.Implementation.dll',
    'Crest.UIExtenderEx.dll', 'Crest.MCM.dll', 'Crest.MCM.UI.Adapter.MCMv5.dll',
    'CREST.v1.4.1.dll',
    'Bannerlord.Harmony.dll', 'Bannerlord.ButterLib.dll',
    'Bannerlord.UIExtenderEx.dll', 'MCMv5.dll',
    '0Harmony.dll', 'Mono.Cecil.dll'
)
$missing = 0
foreach ($n in $musts) {
    $p = Join-Path $bin $n
    if (Test-Path $p) { Write-Host ("  OK   " + $n) -ForegroundColor Green }
    else { Write-Host ("  MISS " + $n) -ForegroundColor Red; $missing++ }
}
if ($missing -gt 0) { exit 3 }
Write-Host ""
Write-Host "==> Re-bundle complete." -ForegroundColor Green
