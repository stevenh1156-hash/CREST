$ErrorActionPreference = 'Continue'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$installBin = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'

Write-Host '==> Check whether deployed CREST.v1.4.1.dll has the Phase N.3 filter (it should NOT after my revert)' -ForegroundColor Cyan
foreach ($name in @('CREST.v1.4.1.dll','Crest.MCM.UI.Adapter.MCMv5.dll')) {
    $p = Join-Path $installBin $name
    if (-not (Test-Path $p)) { continue }
    $f = Get-Item $p
    Write-Host ('   ' + $name + '  ts: ' + $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') + '  size: ' + ([math]::Round($f.Length/1KB)) + ' KB')
    $bytes = [System.IO.File]::ReadAllBytes($p)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    $hasFilter = $text -match 'IsCrestInternalSettingsId'
    Write-Host ('     has IsCrestInternalSettingsId? ' + $hasFilter)
}

Write-Host ''
Write-Host '==> Check src-ui build outputs for the same' -ForegroundColor Cyan
$builds = Get-ChildItem 'C:\dev\bannerlord\Bannerlord.MBOptionScreen' -Recurse -Filter 'CREST.v1.4.1.dll' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch 'obj' }
foreach ($f in $builds | Sort-Object LastWriteTime -Descending) {
    Write-Host ('   ' + $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') + '  ' + $f.FullName)
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    $hasFilter = $text -match 'IsCrestInternalSettingsId'
    Write-Host ('     has IsCrestInternalSettingsId? ' + $hasFilter)
}

Write-Host ''
Write-Host '==> ButterLib options config' -ForegroundColor Cyan
$blOptions = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Mount and Blade II Bannerlord\Configs\ModSettings\ButterLib\Options.json'
if (Test-Path $blOptions) {
    Write-Host ('   ' + $blOptions)
    Get-Content $blOptions | ForEach-Object { Write-Host ('     ' + $_) }
}
