$ErrorActionPreference = 'Continue'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$docs = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Mount and Blade II Bannerlord'

Write-Host '==> BLSE_lasterror.log' -ForegroundColor Cyan
$blseErr = Join-Path $gameRoot 'bin\Win64_Shipping_Client\BLSE_lasterror.log'
if (Test-Path $blseErr) {
    $f = Get-Item $blseErr
    Write-Host ('   ts: ' + $f.LastWriteTime.ToString('HH:mm:ss') + '  size: ' + $f.Length)
    Get-Content $blseErr -Tail 60 | ForEach-Object { Write-Host ('   ' + $_) }
} else { Write-Host '   (none)' }

Write-Host ''
Write-Host '==> Latest default*.log (game-side)' -ForegroundColor Cyan
$gameLog = Get-ChildItem (Join-Path $docs 'Configs\ModLogs') -Filter 'default*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($gameLog) {
    Write-Host ('   ' + $gameLog.Name + '  ts: ' + $gameLog.LastWriteTime.ToString('HH:mm:ss'))
    Get-Content $gameLog.FullName -Tail 40 | ForEach-Object { Write-Host ('   ' + $_) }
}

Write-Host ''
Write-Host '==> ButterLib trace' -ForegroundColor Cyan
$bl = Get-ChildItem (Join-Path $docs 'Configs\ModLogs') -Filter 'butterlib*.txt' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($bl) {
    Write-Host ('   ' + $bl.Name + '  ts: ' + $bl.LastWriteTime.ToString('HH:mm:ss'))
    Get-Content $bl.FullName -Tail 30 | ForEach-Object { Write-Host ('   ' + $_) }
}
