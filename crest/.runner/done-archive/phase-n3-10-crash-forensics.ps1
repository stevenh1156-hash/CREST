$ErrorActionPreference = 'Continue'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$docs = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Mount and Blade II Bannerlord'

Write-Host '==> BLSE_lasterror.log (latest crash from BLSE)' -ForegroundColor Cyan
$blseErr = Join-Path $gameRoot 'bin\Win64_Shipping_Client\BLSE_lasterror.log'
if (Test-Path $blseErr) {
    $f = Get-Item $blseErr
    Write-Host ('   ts: ' + $f.LastWriteTime.ToString('HH:mm:ss') + '  (' + $f.Length + ' bytes)')
    Write-Host '   --- content ---'
    Get-Content $blseErr -Tail 80 | ForEach-Object { Write-Host ('   ' + $_) }
} else {
    Write-Host '   (none)'
}

Write-Host ''
Write-Host '==> Latest game-side log (default*.log)' -ForegroundColor Cyan
$gameLog = Get-ChildItem (Join-Path $docs 'Configs\ModLogs') -Filter 'default*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($gameLog) {
    Write-Host ('   file: ' + $gameLog.Name + '  ts: ' + $gameLog.LastWriteTime.ToString('HH:mm:ss'))
    Write-Host '   --- last 50 lines ---'
    Get-Content $gameLog.FullName -Tail 50 | ForEach-Object { Write-Host ('   ' + $_) }
}

Write-Host ''
Write-Host '==> ButterLib trace log' -ForegroundColor Cyan
$butterLog = Get-ChildItem (Join-Path $docs 'Configs\ModLogs') -Filter 'butterlib*.txt' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($butterLog) {
    Write-Host ('   file: ' + $butterLog.Name + '  ts: ' + $butterLog.LastWriteTime.ToString('HH:mm:ss'))
    Write-Host '   --- last 30 lines ---'
    Get-Content $butterLog.FullName -Tail 30 | ForEach-Object { Write-Host ('   ' + $_) }
}

Write-Host ''
Write-Host '==> BUTR crash report folder?' -ForegroundColor Cyan
$crash = Join-Path $docs 'CrashReports'
if (Test-Path $crash) {
    Get-ChildItem $crash -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 3 | ForEach-Object {
        Write-Host ('   ' + $_.LastWriteTime.ToString('HH:mm:ss') + '  ' + $_.FullName.Substring($crash.Length))
    }
}
