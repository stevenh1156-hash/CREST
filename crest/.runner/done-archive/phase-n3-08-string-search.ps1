$ErrorActionPreference = 'Continue'

# String search: just grep the binary content of each DLL for our distinctive markers.
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$installBin = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'

$markers = @('IsCrestInternalSettingsId', 'MCMUI_v4', 'MCM_v5')

foreach ($name in @('CREST.v1.4.1.dll','Crest.MCM.UI.Adapter.MCMv5.dll','Crest.MCM.dll')) {
    $p = Join-Path $installBin $name
    if (-not (Test-Path $p)) { continue }
    Write-Host ("==> " + $name) -ForegroundColor Cyan
    $bytes = [System.IO.File]::ReadAllBytes($p)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    foreach ($m in $markers) {
        $count = ([regex]::Matches($text, [regex]::Escape($m))).Count
        Write-Host ("   '" + $m + "' occurrences: " + $count)
    }
}

# Also search the build outputs
Write-Host ''
Write-Host '==> Search build outputs for IsCrestInternalSettingsId' -ForegroundColor Cyan
foreach ($f in Get-ChildItem 'C:\dev\bannerlord\Bannerlord.MBOptionScreen' -Recurse -Filter '*.dll' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match 'Stable_Release' -and $_.FullName -notmatch 'obj' }) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ($text -match 'IsCrestInternalSettingsId') {
        Write-Host ('   FOUND in ' + $f.Name + ' (ts ' + $f.LastWriteTime.ToString('HH:mm:ss') + ')') -ForegroundColor Green
    }
}
