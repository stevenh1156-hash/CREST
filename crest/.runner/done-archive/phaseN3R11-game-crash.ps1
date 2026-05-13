$ErrorActionPreference = 'Continue'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$docs = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Mount and Blade II Bannerlord'

Write-Host '==> BUTR crash reports' -ForegroundColor Cyan
$crashDirs = @(
    (Join-Path $docs 'crashes'),
    (Join-Path $docs 'CrashReports'),
    (Join-Path $env:TEMP 'CrashReports'),
    (Join-Path $gameRoot 'Modules\CREST')
)
foreach ($d in $crashDirs) {
    if (Test-Path $d) {
        $recent = Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-15) } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 5
        if ($recent) {
            Write-Host ('   ' + $d + ':')
            foreach ($f in $recent) { Write-Host ('     ' + $f.LastWriteTime.ToString('HH:mm:ss') + '  ' + $f.FullName.Substring($d.Length)) }
        }
    }
}

Write-Host ''
Write-Host '==> Latest game default*.log (full)' -ForegroundColor Cyan
$gameLog = Get-ChildItem (Join-Path $docs 'Configs\ModLogs') -Filter 'default*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($gameLog) {
    Write-Host ('   file: ' + $gameLog.Name + '  ts: ' + $gameLog.LastWriteTime.ToString('HH:mm:ss'))
    Write-Host '   --- last 80 lines ---'
    Get-Content $gameLog.FullName -Tail 80 | ForEach-Object { Write-Host ('   ' + $_) }
}

Write-Host ''
Write-Host '==> Recent CREST runtime.log' -ForegroundColor Cyan
$rt = Join-Path $gameRoot 'Modules\CREST\runtime.log'
if (Test-Path $rt) {
    Get-Content $rt -Tail 30 | ForEach-Object { Write-Host ('   ' + $_) }
}
