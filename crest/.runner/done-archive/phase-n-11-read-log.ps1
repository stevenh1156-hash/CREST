$ErrorActionPreference = 'Continue'

$logFile = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Mount and Blade II Bannerlord\Configs\ModLogs\crest-hide-stubs.log'
Write-Host ("==> Reading " + $logFile) -ForegroundColor Cyan
Write-Host ''

if (Test-Path $logFile) {
    Get-Content $logFile
} else {
    Write-Host "(log file does not exist -- HideCrestStubsPatch.Enable() never ran)" -ForegroundColor Red
}
