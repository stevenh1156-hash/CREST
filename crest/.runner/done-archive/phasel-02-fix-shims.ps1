# Re-run flip-internals on the freshly-built DLLs and regenerate shims
# (previous build skipped this step and shim coverage collapsed).
$ErrorActionPreference = 'Stop'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host '==> flip-internals-public on Crest.X.dll' -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\shims\flip-internals-public.ps1'

Write-Host ''
Write-Host '==> regenerate shims with full type coverage' -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\shims\generate-shims.ps1'

Write-Host ''
Write-Host '==> reassemble + deploy' -ForegroundColor Cyan
$ok = Build-CrestBundle -Version '1.2.0' -SkipBuild
if (-not $ok) { exit 1 }
$ok = Deploy-CrestToBannerlord
if (-not $ok) { exit 2 }

$tmpl = Get-Content 'C:\dev\bannerlord\crest\Modules\CREST\SubModule.xml.template' -Raw
$tmpl = $tmpl -replace '\$version\$', '1.2.0'
Set-Content -Path 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\SubModule.xml' -Value $tmpl -Encoding UTF8

Write-Host ''
Write-Host '==> verify shim sizes recovered' -ForegroundColor Cyan
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
foreach ($n in @('Bannerlord.Harmony.dll','Bannerlord.ButterLib.dll','Bannerlord.UIExtenderEx.dll','MCMv5.dll')) {
    $f = Get-Item (Join-Path $bin $n)
    Write-Host ('  ' + $n + ' : ' + $f.Length + 'B')
}
Write-Host ''
Write-Host '==> Done. Launch and look for CREST in Mod Options.' -ForegroundColor Green
