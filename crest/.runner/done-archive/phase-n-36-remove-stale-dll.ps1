$ErrorActionPreference = 'Continue'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$bin = Join-Path $gameRoot 'bin\Win64_Shipping_Client'
$gameLauncher = Join-Path $bin 'Bannerlord.BLSE.LauncherEx.exe'

# DELETE the stale on-disk LauncherEx.dll so the embedded one (in BLSE.Shared.dll) is used
$staleDll = Join-Path $bin 'Bannerlord.LauncherEx.dll'
if (Test-Path $staleDll) {
    $f = Get-Item $staleDll
    Write-Host ("==> Removing stale " + $staleDll + " (size " + ([math]::Round($f.Length/1KB)) + " KB, dated " + $f.LastWriteTime.ToString('HH:mm:ss') + ")") -ForegroundColor Yellow
    Remove-Item $staleDll -Force
} else {
    Write-Host '   (no stale LauncherEx.dll on disk)' -ForegroundColor DarkGray
}

# Clear logs
foreach ($f in @('C:\dev\bannerlord\launcherex-launch.log','C:\dev\bannerlord\manager-enable.log','C:\dev\bannerlord\hide-debug.log')) {
    if (Test-Path $f) { Remove-Item $f -Force }
}

# Launch
$proc = Start-Process -FilePath $gameLauncher -WorkingDirectory $bin -PassThru
Start-Sleep -Seconds 14
if (-not $proc.HasExited) { Write-Host ('running ' + $proc.Modules.Count + ' modules') -ForegroundColor Green; Stop-Process -Id $proc.Id -Force }
else { Write-Host ('EXITED code=' + $proc.ExitCode) -ForegroundColor Red }

foreach ($p in @('C:\dev\bannerlord\launcherex-launch.log','C:\dev\bannerlord\manager-enable.log','C:\dev\bannerlord\hide-debug.log')) {
    Write-Host ''
    Write-Host ('==> ' + (Split-Path $p -Leaf)) -ForegroundColor Cyan
    if (Test-Path $p) { Get-Content $p | ForEach-Object { Write-Host ('   ' + $_) -ForegroundColor Green } } else { Write-Host '   (none)' -ForegroundColor Red }
}
