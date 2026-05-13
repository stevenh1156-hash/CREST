$ErrorActionPreference = 'Continue'

Write-Host '==> Bannerlord launcher / game processes' -ForegroundColor Cyan
Get-Process | Where-Object { $_.ProcessName -match 'Bannerlord|TaleWorlds' } |
    Select-Object Id, ProcessName, StartTime, MainWindowTitle |
    Format-Table -AutoSize

Write-Host ''
Write-Host '==> Loaded modules in any running launcher process' -ForegroundColor Cyan
$proc = Get-Process | Where-Object { $_.ProcessName -match 'Launcher' } | Select-Object -First 1
if ($proc) {
    Write-Host ("   PID " + $proc.Id + " started at " + $proc.StartTime.ToString('HH:mm:ss'))
    $blseLoaded = $proc.Modules | Where-Object { $_.ModuleName -match 'LauncherEx' }
    foreach ($m in $blseLoaded) {
        Write-Host ("   " + $m.ModuleName + " from " + $m.FileName)
        if (Test-Path $m.FileName) {
            $f = Get-Item $m.FileName
            Write-Host ("      written: " + $f.LastWriteTime.ToString('HH:mm:ss') + "  size: " + $f.Length + "B")
        }
    }
} else {
    Write-Host "   (no launcher process running)"
}
