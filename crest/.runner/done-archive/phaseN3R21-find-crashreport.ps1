$ErrorActionPreference = 'Continue'
$docs = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Mount and Blade II Bannerlord'

Write-Host '==> Wide scan for any HTML/JSON crash report written in last 10 min' -ForegroundColor Cyan
$search = @($docs, $env:TEMP, $env:LOCALAPPDATA, 'C:\Users\Steve\AppData\Roaming')
foreach ($root in $search) {
    if (-not (Test-Path $root)) { continue }
    Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.LastWriteTime -gt (Get-Date).AddMinutes(-10)) -and
            ($_.Name -match '\.(html|htm|zip|json|crash)$') -and
            ($_.FullName -notmatch 'AppData\\Roaming\\Claude' -and $_.FullName -notmatch 'cache' -and $_.FullName -notmatch '\.runner')
        } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 10 | ForEach-Object {
            Write-Host ('   ' + $_.LastWriteTime.ToString('HH:mm:ss') + '  ' + $_.FullName)
        }
}

Write-Host ''
Write-Host '==> CrashReports dir contents anywhere' -ForegroundColor Cyan
foreach ($d in @(
    (Join-Path $docs 'CrashReports'),
    (Join-Path $docs 'crashes'),
    (Join-Path $env:LOCALAPPDATA 'BUTR'),
    (Join-Path $env:LOCALAPPDATA 'Bannerlord'),
    'C:\Users\Steve\AppData\LocalLow\Bannerlord',
    'C:\Users\Steve\AppData\LocalLow\TaleWorlds Entertainment',
    'C:\Users\Steve\AppData\LocalLow'
)) {
    if (Test-Path $d) {
        Write-Host ('   ' + $d + ':')
        Get-ChildItem $d -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 3 | ForEach-Object {
            Write-Host ('     ' + $_.LastWriteTime.ToString('HH:mm:ss') + '  ' + $_.Name)
        }
    }
}
