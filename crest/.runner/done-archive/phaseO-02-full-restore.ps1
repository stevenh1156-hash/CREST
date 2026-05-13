$ErrorActionPreference = 'Stop'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$staging = 'C:\dev\bannerlord\crest\dist\CREST'
$installCrest = Join-Path $gameRoot 'Modules\CREST'
$installBin = Join-Path $installCrest 'bin\Win64_Shipping_Client'

Write-Host '==> Wipe + restore bin from staging (49 files)' -ForegroundColor Cyan
if (Test-Path $installBin) { Remove-Item -Recurse -Force $installBin }
New-Item -ItemType Directory -Path $installBin -Force | Out-Null
Copy-Item -Path (Join-Path $staging 'bin\Win64_Shipping_Client\*') -Destination $installBin -Recurse -Force

Write-Host '==> Restore SubModule.xml via WriteAllText' -ForegroundColor Cyan
$content = [System.IO.File]::ReadAllText((Join-Path $staging 'SubModule.xml'))
[System.IO.File]::WriteAllText((Join-Path $installCrest 'SubModule.xml'), $content, [System.Text.Encoding]::UTF8)

Write-Host '==> Overlay fresh Phase O Crest.Harmony.dll' -ForegroundColor Cyan
$harmonyDll = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll'
Copy-Item $harmonyDll (Join-Path $installBin 'Crest.Harmony.dll') -Force
Write-Host ('   Crest.Harmony.dll ts: ' + (Get-Item (Join-Path $installBin 'Crest.Harmony.dll')).LastWriteTime.ToString('HH:mm:ss')) -ForegroundColor Green

Write-Host '==> Overlay fresh MCM rebuild outputs (with N.3 filter)' -ForegroundColor Cyan
$uiOut = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI\bin\Stable_Release\netstandard2.0'
foreach ($f in 'CREST.v1.4.1.dll','Crest.MCM.UI.Adapter.MCMv5.dll','Bannerlord.ModuleLoader.CREST.dll') {
    $src = Join-Path $uiOut $f
    if (Test-Path $src) { Copy-Item $src (Join-Path $installBin $f) -Force }
}

# Verify
$count = (Get-ChildItem $installBin -File).Count
$lines = (Get-Content (Join-Path $installCrest 'SubModule.xml')).Count
Write-Host ''
Write-Host ('==> Final: bin=' + $count + ' files, SubModule.xml=' + $lines + ' lines') -ForegroundColor Cyan
foreach ($n in '0Harmony.dll','Crest.Harmony.dll','Crest.ButterLib.dll','CREST.v1.4.1.dll') {
    $p = Join-Path $installBin $n
    Write-Host ('   ' + (Test-Path $p) + '  ' + $n + '  ts: ' + (Get-Item $p).LastWriteTime.ToString('HH:mm:ss'))
}

Write-Host ''
Write-Host '==> Launch from Steam now.' -ForegroundColor Yellow
