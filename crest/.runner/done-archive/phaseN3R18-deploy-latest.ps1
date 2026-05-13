$ErrorActionPreference = 'Continue'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$installBin = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'
$uiOut = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI\bin\Stable_Release\netstandard2.0'

Write-Host '==> Force-deploy latest build outputs (overwrite stale staging copies)' -ForegroundColor Cyan
foreach ($f in 'CREST.v1.4.1.dll','Crest.MCM.UI.Adapter.MCMv5.dll','Bannerlord.ModuleLoader.CREST.dll','Crest.MCM.dll','MCMv5.dll') {
    $src = Join-Path $uiOut $f
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $installBin $f) -Force
        $df = Get-Item (Join-Path $installBin $f)
        Write-Host ('   ' + $f + '  ts: ' + $df.LastWriteTime.ToString('HH:mm:ss')) -ForegroundColor Green
    }
}

Write-Host ''
Write-Host '==> Verify .Where filter is NOT in deployed CREST.v1.4.1.dll IL' -ForegroundColor Cyan
$dl = Join-Path $installBin 'CREST.v1.4.1.dll'
$bytes = [System.IO.File]::ReadAllBytes($dl)
$text = [System.Text.Encoding]::UTF8.GetString($bytes)
# The dead helper method is still in there, but to detect whether the FILTER is wired
# we'd need IL inspection. The presence of the string is not conclusive. Just confirm
# the deployed DLL has the latest timestamp.
Write-Host ('   ts: ' + (Get-Item $dl).LastWriteTime.ToString('HH:mm:ss'))
Write-Host ('   has IsCrestInternalSettingsId string? ' + ($text -match 'IsCrestInternalSettingsId'))

Write-Host ''
Write-Host '==> Now relaunch via Steam.' -ForegroundColor Yellow
