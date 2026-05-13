# Deep diagnostic round 2: error has changed from "dependency conflict" to
# "application faced a problem during the loading screen". So we're past the
# launcher's pre-check; now something is throwing during module init.
#
# Pull: full runtime.log tail, all RESOLVE-MISS, all FIRST-CHANCE exceptions,
# Bannerlord crash logs, BetterExceptionWindow output if any.

$ErrorActionPreference = 'Continue'

$documents   = [Environment]::GetFolderPath('MyDocuments')
$cfgRoot     = Join-Path $documents 'Mount and Blade II Bannerlord'
$runtimeLog  = 'C:\dev\bannerlord\crest\runtime.log'

Write-Host "==> runtime.log meta" -ForegroundColor Cyan
if (Test-Path $runtimeLog) {
    $f = Get-Item $runtimeLog
    Write-Host ("  size: {0:N0} bytes  modified: {1}" -f $f.Length, $f.LastWriteTime)
} else {
    Write-Host "  not found" -ForegroundColor Red
    exit 1
}

$lines = Get-Content $runtimeLog
Write-Host ("  total lines: {0}" -f $lines.Count)

Write-Host ""
Write-Host "==> last 20 LOAD entries (where did module loading reach?)" -ForegroundColor Cyan
$lines | Where-Object { $_ -match 'LOAD\s' } | Select-Object -Last 20 | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "==> all RESOLVE-MISS (assemblies the runtime couldn't find)" -ForegroundColor Cyan
$lines | Where-Object { $_ -match 'RESOLVE-MISS' } | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }

Write-Host ""
Write-Host "==> all FIRST-CHANCE exception headers" -ForegroundColor Cyan
$lines | Where-Object { $_ -match 'FIRST-CHANCE\s+System\.' } | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }

Write-Host ""
Write-Host "==> last 80 lines (raw tail)" -ForegroundColor Cyan
$lines | Select-Object -Last 80 | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "==> Game CrashLogs folder" -ForegroundColor Cyan
$crashRoots = @(
    (Join-Path $cfgRoot 'CrashLogs'),
    (Join-Path $cfgRoot 'CrashReports'),
    (Join-Path $cfgRoot 'CrashUploads'),
    (Join-Path $cfgRoot 'logs'),
    (Join-Path $cfgRoot 'Logs')
)
foreach ($cr in $crashRoots) {
    if (Test-Path $cr) {
        Write-Host "  $cr :" -ForegroundColor White
        Get-ChildItem $cr -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 5 |
            ForEach-Object { Write-Host ("    {0}  {1,8:N0}B  {2}" -f $_.LastWriteTime, $_.Length, $_.Name) }
    }
}

Write-Host ""
Write-Host "==> CREST runtime files (look for ButterLib log, MCM log)" -ForegroundColor Cyan
$crestPaths = @(
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\ButterLib',
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST',
    (Join-Path $cfgRoot 'Configs')
)
foreach ($p in $crestPaths) {
    if (Test-Path $p) {
        $logs = Get-ChildItem $p -Filter '*.log' -Recurse -ErrorAction SilentlyContinue
        if ($logs) {
            foreach ($l in $logs) {
                Write-Host ("    {0,8:N0}B  {1}" -f $l.Length, $l.FullName)
            }
        }
    }
}
