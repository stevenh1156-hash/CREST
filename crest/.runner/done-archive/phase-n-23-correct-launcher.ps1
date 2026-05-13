$ErrorActionPreference = 'Continue'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$launcher = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.BLSE.LauncherEx.exe'

Write-Host ("==> Launching the BLSE launcher: " + (Split-Path $launcher -Leaf)) -ForegroundColor Cyan

# Clear all candidate log paths
$candidates = @(
    'C:\Temp\crest-hide-stubs.log',
    'C:\dev\bannerlord\crest\crest-hide-stubs-launcher.log',
    (Join-Path $env:TEMP 'crest-hide-stubs.log'),
    (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Mount and Blade II Bannerlord\Configs\ModLogs\crest-hide-stubs.log')
)
foreach ($p in $candidates) { if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue } }

# Launch
$proc = Start-Process -FilePath $launcher -PassThru
Start-Sleep -Seconds 14
$proc.Refresh()
if ($proc.HasExited) {
    Write-Host ('   EXITED early code=' + $proc.ExitCode) -ForegroundColor Red
} else {
    Write-Host ('   running OK with ' + $proc.Modules.Count + ' modules') -ForegroundColor Green
    Stop-Process -Id $proc.Id -Force
}

Write-Host ''
Write-Host '==> Which candidate log paths got written?' -ForegroundColor Cyan
foreach ($p in $candidates) {
    if (Test-Path $p) {
        Write-Host ('   FOUND ' + $p) -ForegroundColor Green
        Get-Content $p | ForEach-Object { Write-Host ('     ' + $_) }
    } else {
        Write-Host ('   none  ' + $p) -ForegroundColor DarkGray
    }
}
