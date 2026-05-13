$ErrorActionPreference = 'Continue'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$installCrest = Join-Path $gameRoot 'Modules\CREST'
$installBin = Join-Path $installCrest 'bin\Win64_Shipping_Client'

Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

# Capture current SubModule.xml for backup before MCM rebuild touches it.
$smXml = Join-Path $installCrest 'SubModule.xml'
$beforeLines = (Get-Content $smXml).Count
Write-Host ('==> Pre-build SubModule.xml line count: ' + $beforeLines) -ForegroundColor Cyan

Write-Host ''
Write-Host '==> Build MCM (with N.3 filter re-added; _Module/SubModule.xml now has CREST content)' -ForegroundColor Cyan
$ok = Build-CrestRepo -Name MCM
if (-not $ok) { Write-Host 'build FAILED' -ForegroundColor Red; exit 1 }

# Verify SubModule.xml wasn't corrupted by the build
$afterLines = (Get-Content $smXml).Count
$afterContent = Get-Content $smXml -Raw
Write-Host ''
Write-Host ('==> Post-build SubModule.xml: ' + $afterLines + ' lines') -ForegroundColor Cyan
Write-Host ('   has Crest.Harmony.dll? ' + ($afterContent -match 'Crest\.Harmony\.dll'))
Write-Host ('   has CREST.v1.4.1.dll?  ' + ($afterContent -match 'CREST\.v1\.4\.1\.dll'))
if ($afterContent -notmatch 'Crest\.Harmony\.dll') {
    Write-Host '   SubModule.xml is wrong, force-restoring from staging' -ForegroundColor Yellow
    $stagingXml = 'C:\dev\bannerlord\crest\dist\CREST\SubModule.xml'
    $content = [System.IO.File]::ReadAllText($stagingXml)
    [System.IO.File]::WriteAllText($smXml, $content, [System.Text.Encoding]::UTF8)
    Write-Host ('   restored to ' + (Get-Content $smXml).Count + ' lines') -ForegroundColor Green
}

# Deploy the freshly-built MCM UI Adapter + version DLL
Write-Host ''
Write-Host '==> Deploy fresh MCM build outputs' -ForegroundColor Cyan
$uiOut = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI\bin\Stable_Release\netstandard2.0'
foreach ($f in 'CREST.v1.4.1.dll','Crest.MCM.UI.Adapter.MCMv5.dll','Bannerlord.ModuleLoader.CREST.dll') {
    $src = Join-Path $uiOut $f
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $installBin $f) -Force
        $df = Get-Item (Join-Path $installBin $f)
        Write-Host ('   ' + $f + '  ts: ' + $df.LastWriteTime.ToString('HH:mm:ss')) -ForegroundColor Green
    }
}

Write-Host ''
Write-Host '==> Final SubModule.xml line count: ' -NoNewline
$finalLines = (Get-Content $smXml).Count
Write-Host $finalLines

Write-Host ''
Write-Host '==> Now relaunch via Steam, open Mod Options. Should see CREST + consumer mods, no internal entries.' -ForegroundColor Yellow
