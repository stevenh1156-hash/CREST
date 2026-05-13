# =====================================================================
# Crest-Watchdog.ps1 -- keeps the watcher alive.
# =====================================================================
# Polls events.log heartbeat every 30 sec. If the last entry is older
# than 120 sec, kills any orphan watcher PowerShell processes, then
# respawns the watcher elevated via Crest-Boot.ps1 (which spawns it
# in its own admin window).
#
# Solves the "watcher silently died" symptom we hit twice today.
# Run in its own non-admin PowerShell window (Start-Process -Verb RunAs
# inside Crest-Boot.ps1 handles the elevation for the spawned watcher).
#
# Usage:
#   & C:\dev\bannerlord\crest\Crest-Watchdog.ps1
# =====================================================================

$ErrorActionPreference = 'Continue'

$crestRoot   = 'C:\dev\bannerlord\crest'
$eventsLog   = Join-Path $crestRoot '.runner\events.log'
$bootScript  = Join-Path $crestRoot 'Crest-Boot.ps1'
$watcherPath = Join-Path $crestRoot 'tools\crest-dev.ps1'

$pollSec     = 30
$staleSec    = 120

Write-Host ''
Write-Host '=========================================================' -ForegroundColor Cyan
Write-Host '  CREST Watcher Watchdog' -ForegroundColor Cyan
Write-Host '=========================================================' -ForegroundColor Cyan
Write-Host "  events.log:   $eventsLog"
Write-Host "  poll every:   ${pollSec}s"
Write-Host "  stale after:  ${staleSec}s"
Write-Host '  press Ctrl+C to stop' -ForegroundColor DarkGray
Write-Host ''

function Get-LastHeartbeatAge {
    if (-not (Test-Path $eventsLog)) { return [TimeSpan]::MaxValue }
    try {
        $last = Get-Content $eventsLog -Tail 1 -ErrorAction SilentlyContinue
        if ($last -match '^\[(.+?)\]') {
            $ts = [DateTime]::Parse($Matches[1])
            return (Get-Date) - $ts
        }
    } catch { }
    return [TimeSpan]::MaxValue
}

function Get-OrphanWatcherProcesses {
    # Find PS processes whose command line contains crest-dev.ps1.
    # On Windows we can use CIM/WMI for command line introspection.
    try {
        $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                 Where-Object {
                     ($_.Name -in 'powershell.exe','pwsh.exe') -and
                     ($_.CommandLine -like '*crest-dev.ps1*')
                 }
        return $procs
    } catch {
        return @()
    }
}

function Restart-Watcher {
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] watcher STALE -- restarting" -ForegroundColor Yellow

    # 1. Kill any orphans.
    $orphans = Get-OrphanWatcherProcesses
    foreach ($p in $orphans) {
        try {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
            Write-Host "  killed orphan PID=$($p.ProcessId)" -ForegroundColor DarkYellow
        } catch { }
    }

    # 2. Spawn fresh watcher via boot script (handles elevation).
    if (-not (Test-Path $bootScript)) {
        Write-Host "  ERROR: $bootScript not found -- cannot restart" -ForegroundColor Red
        return
    }

    # We can't run Crest-Boot.ps1 in this same window (it would block
    # waiting for menu choice). Instead, spawn the watcher directly via
    # Start-Process -Verb RunAs (elevated) in a new admin window.
    $args = @('-NoExit', '-ExecutionPolicy', 'Bypass', '-File', "`"$watcherPath`"")
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -WorkingDirectory $crestRoot | Out-Null
        Write-Host '  watcher spawn requested (UAC may prompt)' -ForegroundColor Green
    } catch {
        Write-Host "  ERROR spawning watcher: $($_.Exception.Message)" -ForegroundColor Red
    }
}

while ($true) {
    $age = Get-LastHeartbeatAge
    $stamp = (Get-Date).ToString('HH:mm:ss')
    if ($age.TotalSeconds -lt $staleSec) {
        Write-Host "[$stamp] watcher OK (last heartbeat ${[int]$age.TotalSeconds}s ago)" -ForegroundColor DarkGray
    } else {
        Restart-Watcher
        Start-Sleep -Seconds 30  # give the new watcher time to come up
    }
    Start-Sleep -Seconds $pollSec
}
