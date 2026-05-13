$ErrorActionPreference = 'Continue'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'

Write-Host '==> Crash forensics' -ForegroundColor Cyan

# 1. BLSE_lasterror.log
$blseErr = Join-Path $gameRoot 'bin\Win64_Shipping_Client\BLSE_lasterror.log'
if (Test-Path $blseErr) {
    Write-Host ''
    Write-Host '   BLSE_lasterror.log (last 40 lines):' -ForegroundColor Yellow
    Get-Content $blseErr -Tail 40 | ForEach-Object { Write-Host ('     ' + $_) }
} else {
    Write-Host '   no BLSE_lasterror.log'
}

# 2. Most recent Windows app crash event (Bannerlord launcher)
Write-Host ''
Write-Host '   Recent application errors (last 5 min) for the launcher:' -ForegroundColor Yellow
$start = (Get-Date).AddMinutes(-10)
try {
    Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$start; Level=2} -MaxEvents 10 -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match 'Bannerlord|TaleWorlds|MountAndBlade|LauncherEx' } |
        Select-Object -First 5 | ForEach-Object {
            Write-Host ('     ' + $_.TimeCreated.ToString('HH:mm:ss') + '  ' + $_.ProviderName)
            Write-Host ('       ' + ($_.Message -split "`n" | Select-Object -First 6 | Out-String))
        }
} catch { Write-Host '     (could not read event log)' -ForegroundColor DarkGray }

# 3. The launcher's .exe.config in full
Write-Host ''
Write-Host '   Launcher .exe.config (full):' -ForegroundColor Yellow
Get-Content (Join-Path $gameRoot 'bin\Win64_Shipping_Client\TaleWorlds.MountAndBlade.Launcher.exe.config') |
    ForEach-Object { Write-Host ('     ' + $_) }
