$ErrorActionPreference = 'Stop'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$staging = 'C:\dev\bannerlord\crest\dist\CREST'
$installCrest = Join-Path $gameRoot 'Modules\CREST'
$installBin = Join-Path $installCrest 'bin\Win64_Shipping_Client'

Write-Host '==> Wipe Modules\CREST\bin and restore from staging' -ForegroundColor Cyan
if (Test-Path $installBin) { Remove-Item -Recurse -Force $installBin }
New-Item -ItemType Directory -Path $installBin -Force | Out-Null
Copy-Item -Path (Join-Path $staging 'bin\Win64_Shipping_Client\*') -Destination $installBin -Recurse -Force
$count = (Get-ChildItem $installBin -File).Count
Write-Host ('   ' + $count + ' files restored to bin') -ForegroundColor Green

Write-Host ''
Write-Host '==> Restore SubModule.xml via WriteAllText (the COPY-Item-truncates bug)' -ForegroundColor Cyan
$content = [System.IO.File]::ReadAllText((Join-Path $staging 'SubModule.xml'))
[System.IO.File]::WriteAllText((Join-Path $installCrest 'SubModule.xml'), $content, [System.Text.Encoding]::UTF8)
$lines = (Get-Content (Join-Path $installCrest 'SubModule.xml')).Count
Write-Host ('   wrote SubModule.xml: ' + $lines + ' lines') -ForegroundColor Green

# Add the MCM-rebuilt CREST.v1.4.1.dll on top so the Phase N.3 filter is active
Write-Host ''
Write-Host '==> Overlay latest MCM build outputs (with Phase N.3 filter)' -ForegroundColor Cyan
$uiOut = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI\bin\Stable_Release\netstandard2.0'
foreach ($f in 'CREST.v1.4.1.dll','Crest.MCM.UI.Adapter.MCMv5.dll','Bannerlord.ModuleLoader.CREST.dll') {
    $src = Join-Path $uiOut $f
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $installBin $f) -Force
        Write-Host ('   ' + $f + '  ts: ' + (Get-Item (Join-Path $installBin $f)).LastWriteTime.ToString('HH:mm:ss')) -ForegroundColor Green
    }
}

# Final verification
Write-Host ''
Write-Host '==> Final state' -ForegroundColor Cyan
$count = (Get-ChildItem $installBin -File).Count
$lines = (Get-Content (Join-Path $installCrest 'SubModule.xml')).Count
Write-Host ('   bin file count: ' + $count + ' (expected ~50)')
Write-Host ('   SubModule.xml lines: ' + $lines + ' (expected 129)')
foreach ($n in '0Harmony.dll','Crest.Harmony.dll','Crest.ButterLib.dll','CREST.v1.4.1.dll','Bannerlord.Harmony.dll','MCMv5.dll','Mono.Cecil.dll') {
    $exists = Test-Path (Join-Path $installBin $n)
    Write-Host ('   ' + $exists + '  ' + $n)
}

Write-Host ''
Write-Host '==> READY: launch from Steam.' -ForegroundColor Yellow
