$ErrorActionPreference = 'Continue'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$bin = Join-Path $gameRoot 'bin\Win64_Shipping_Client'
$gameLauncher = Join-Path $bin 'Bannerlord.BLSE.LauncherEx.exe'

# Clear logs
foreach ($f in @('C:\dev\bannerlord\manager-enable.log','C:\dev\bannerlord\hide-debug.log')) {
    if (Test-Path $f) { Remove-Item $f -Force }
}

Write-Host "==> Launching with CWD=$bin (the right CWD!)" -ForegroundColor Cyan
$proc = Start-Process -FilePath $gameLauncher -WorkingDirectory $bin -PassThru
Start-Sleep -Seconds 14
$proc.Refresh()
if ($proc.HasExited) {
    Write-Host ('   EXITED code=' + $proc.ExitCode) -ForegroundColor Red
} else {
    Write-Host ('   running ' + $proc.Modules.Count + ' modules') -ForegroundColor Green
    Stop-Process -Id $proc.Id -Force
}

Write-Host ''
Write-Host '==> manager-enable.log:' -ForegroundColor Cyan
if (Test-Path 'C:\dev\bannerlord\manager-enable.log') {
    Get-Content 'C:\dev\bannerlord\manager-enable.log' | ForEach-Object { Write-Host ('   ' + $_) -ForegroundColor Green }
} else { Write-Host '   not written' -ForegroundColor Red }

Write-Host ''
Write-Host '==> hide-debug.log:' -ForegroundColor Cyan
if (Test-Path 'C:\dev\bannerlord\hide-debug.log') {
    Get-Content 'C:\dev\bannerlord\hide-debug.log' | ForEach-Object { Write-Host ('   ' + $_) -ForegroundColor Green }
} else { Write-Host '   not written' -ForegroundColor Red }
