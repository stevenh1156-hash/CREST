$ErrorActionPreference = 'Continue'

$logFile = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Mount and Blade II Bannerlord\Configs\ModLogs\crest-hide-stubs.log'
Write-Host ("==> " + $logFile) -ForegroundColor Cyan
Write-Host ''
if (Test-Path $logFile) {
    Get-Content $logFile
} else {
    Write-Host "(file does not exist -- HideCrestStubsPatch.Enable() did not run)" -ForegroundColor Red
    Write-Host ''
    Write-Host '==> Recent log files written today (any)' -ForegroundColor Cyan
    $modLogs = Split-Path $logFile -Parent
    Get-ChildItem $modLogs -File | Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-10) } |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object { Write-Host ("   " + $_.LastWriteTime.ToString('HH:mm:ss') + "  " + $_.Name) }
}
