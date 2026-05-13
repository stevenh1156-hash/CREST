$ErrorActionPreference = 'Continue'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$installBin = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'
$docs = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Mount and Blade II Bannerlord'

Write-Host '==> CREST/bin state RIGHT NOW (during crash dialog)' -ForegroundColor Cyan
$count = (Get-ChildItem $installBin -File -ErrorAction SilentlyContinue).Count
Write-Host ('   total: ' + $count + ' files')

Write-Host ''
Write-Host '==> All recently-modified files everywhere we care about (last 10 min)' -ForegroundColor Cyan
foreach ($d in @($installBin, (Join-Path $docs 'Configs\ModLogs'), (Join-Path $docs 'crashes'), (Join-Path $env:TEMP 'CrashReports'))) {
    if (-not (Test-Path $d)) { continue }
    Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-10) } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 10 | ForEach-Object {
            Write-Host ('   ' + $_.LastWriteTime.ToString('HH:mm:ss') + '  ' + $_.FullName)
        }
}

Write-Host ''
Write-Host '==> default*.log latest 50 lines' -ForegroundColor Cyan
$gameLog = Get-ChildItem (Join-Path $docs 'Configs\ModLogs') -Filter 'default*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($gameLog) {
    Write-Host ('   ' + $gameLog.Name + '  ts: ' + $gameLog.LastWriteTime.ToString('HH:mm:ss'))
    Get-Content $gameLog.FullName -Tail 50 | ForEach-Object { Write-Host ('   ' + $_) }
}

Write-Host ''
Write-Host '==> All BUTR crash report locations' -ForegroundColor Cyan
foreach ($d in @(
    (Join-Path $docs 'crashes'),
    (Join-Path $docs 'CrashReports'),
    (Join-Path $env:TEMP 'CrashReports'),
    (Join-Path $env:LOCALAPPDATA 'CrashReports'),
    (Join-Path $gameRoot 'Modules\CREST\CrashReports')
)) {
    if (Test-Path $d) {
        $r = Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 3
        if ($r) {
            Write-Host ('   ' + $d + ':')
            foreach ($f in $r) { Write-Host ('     ' + $f.LastWriteTime.ToString('HH:mm:ss') + '  ' + $f.FullName.Substring($d.Length)) }
        }
    }
}
