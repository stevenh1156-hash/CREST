$ErrorActionPreference = 'Continue'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$launcher = Join-Path $gameRoot 'bin\Win64_Shipping_Client\TaleWorlds.MountAndBlade.Launcher.exe'

Write-Host ("==> Launcher exe: " + $launcher) -ForegroundColor Cyan
if (-not (Test-Path $launcher)) { Write-Host '   NOT FOUND' -ForegroundColor Red; exit 1 }
Write-Host ('   ' + (Get-Item $launcher).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))

# Clear our debug log so we know what's fresh
$logFile = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Mount and Blade II Bannerlord\Configs\ModLogs\crest-hide-stubs.log'
if (Test-Path $logFile) { Remove-Item $logFile -Force }

# Confirm the launcher .exe.config has the AppDomainManager redirect
$cfg = $launcher + '.config'
Write-Host ''
Write-Host '==> Launcher .exe.config' -ForegroundColor Cyan
if (Test-Path $cfg) {
    $cfgContent = Get-Content $cfg -Raw
    if ($cfgContent -match 'BLSE\.Loaders\.AppDomainManager') {
        Write-Host '   appDomainManagerType redirect: PRESENT' -ForegroundColor Green
    } else {
        Write-Host '   appDomainManagerType redirect: MISSING' -ForegroundColor Red
    }
    if ($cfgContent -match 'AppDomainManagerAssembly') {
        $a = ([regex]::Match($cfgContent, 'AppDomainManagerAssembly="([^"]+)"').Groups[1].Value)
        Write-Host ("   AppDomainManagerAssembly = " + $a)
    }
} else {
    Write-Host "   NOT FOUND" -ForegroundColor Red
}

# Launch the launcher programmatically
Write-Host ''
Write-Host '==> Launching TaleWorlds.MountAndBlade.Launcher.exe' -ForegroundColor Cyan
$proc = Start-Process -FilePath $launcher -PassThru
Write-Host ("   PID: " + $proc.Id + "  started at " + (Get-Date).ToString('HH:mm:ss'))

# Wait up to 25 seconds for the launcher to render
Start-Sleep -Seconds 12

# Check process state and loaded modules
$proc.Refresh()
Write-Host ''
Write-Host '==> After 12s' -ForegroundColor Cyan
if (-not $proc.HasExited) {
    Write-Host ('   running, ' + $proc.Modules.Count + ' modules loaded')
    $blse = $proc.Modules | Where-Object { $_.ModuleName -match 'BLSE|LauncherEx' } | Select-Object -First 5
    foreach ($m in $blse) {
        Write-Host ('   ' + $m.ModuleName + ' -> ' + (Split-Path $m.FileName -Leaf))
    }
} else {
    Write-Host ('   EXITED early, code=' + $proc.ExitCode) -ForegroundColor Red
}

# Read log
Write-Host ''
Write-Host '==> Debug log after launch' -ForegroundColor Cyan
if (Test-Path $logFile) {
    Write-Host '   FOUND:' -ForegroundColor Green
    Get-Content $logFile | ForEach-Object { Write-Host ('   ' + $_) }
} else {
    Write-Host '   not written' -ForegroundColor Red
}

# Kill the launcher
if (-not $proc.HasExited) {
    Stop-Process -Id $proc.Id -Force
    Write-Host ''
    Write-Host '   killed launcher' -ForegroundColor DarkGray
}
