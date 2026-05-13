# =====================================================================
# Crest-Boot.ps1 -- one-step CREST boot.
# =====================================================================
# Run this from a desktop shortcut or a fresh PowerShell. It will:
#   1. Check whether the watcher is alive (events.log heartbeat < 90 s).
#   2. If dead, spawn it in a new admin PS window (crest-dev.ps1).
#   3. Wait for the watcher's first heartbeat (up to 30 s).
#   4. Open Crest.ps1 -Mode Menu in the current window.
#
# Designed so a player who knows nothing about PowerShell can double-click
# a shortcut to this file and reach the menu in one step.
#
# Usage:
#   right-click -> Run with PowerShell
#   or:  & C:\dev\bannerlord\crest\Crest-Boot.ps1
# =====================================================================

param(
    [string]$Mode = 'Menu',
    [string]$Arg  = ''
)

$ErrorActionPreference = 'Continue'

$crestRoot   = 'C:\dev\bannerlord\crest'
# Watcher script lives under tools\ in this project layout. Try the canonical
# path first, then fall back to other plausible locations so a future move
# doesn't break the boot script.
$watcherCandidates = @(
    (Join-Path $crestRoot 'tools\crest-dev.ps1'),
    (Join-Path $crestRoot 'crest-dev.ps1'),
    (Join-Path $crestRoot 'tools\watcher.ps1')
)
$watcherPath = $watcherCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $watcherPath) { $watcherPath = $watcherCandidates[0] }   # for the error message below

$entryPath   = Join-Path $crestRoot 'Crest.ps1'
$eventsLog   = Join-Path $crestRoot '.runner\events.log'
$runnerDir   = Join-Path $crestRoot '.runner'

# Ensure runner dir exists so the watcher has somewhere to write events.
if (-not (Test-Path $runnerDir)) {
    New-Item -ItemType Directory -Path $runnerDir -Force | Out-Null
}

function Test-WatcherAlive {
    # Dual-check: a fresh heartbeat AND a live PowerShell process running
    # crest-dev.ps1. The heartbeat alone can be a stale leftover from a
    # watcher that already exited -- that's how we ended up with menus
    # claiming "ALIVE" while nothing was actually processing the queue.
    $heartbeatOk = $false
    if (Test-Path $eventsLog) {
        try {
            $last = Get-Content $eventsLog -Tail 1 -ErrorAction SilentlyContinue
            if ($last -match '^\[(.+?)\]') {
                $ts = [DateTime]::Parse($Matches[1])
                $heartbeatOk = ((Get-Date) - $ts).TotalSeconds -lt 90
            }
        } catch { }
    }
    if (-not $heartbeatOk) { return $false }

    # Now check that a watcher process is actually running.
    try {
        $proc = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                Where-Object {
                    ($_.Name -in 'powershell.exe','pwsh.exe') -and
                    ($_.CommandLine -like '*crest-dev.ps1*')
                }
        return ($proc -ne $null)
    } catch {
        # Fall back to heartbeat-only if CIM is unavailable.
        return $heartbeatOk
    }
}

function Test-IsAdmin {
    $id  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $pri = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $pri.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Test if any PowerShell process is already running a script whose filename
# matches the supplied leaf name. Prevents spawning duplicate daemons when
# Crest-Boot is invoked repeatedly.
function Test-DaemonRunning {
    param([string]$ScriptLeaf)
    try {
        $proc = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                Where-Object {
                    ($_.Name -in 'powershell.exe','pwsh.exe') -and
                    ($_.CommandLine -like ('*' + $ScriptLeaf + '*'))
                }
        return ($proc -ne $null)
    } catch {
        return $false
    }
}

# Spawn an auxiliary daemon if it isn't already running. Each daemon runs
# in its own PS window so it can be Ctrl+C'd or closed independently.
function Start-AuxDaemon {
    param(
        [string]$Path,
        [string]$Label
    )
    $leaf = Split-Path -Leaf $Path
    if (-not (Test-Path $Path)) {
        Write-Host ("        $Label : skipped (not found at $Path)") -ForegroundColor DarkGray
        return
    }
    if (Test-DaemonRunning -ScriptLeaf $leaf) {
        Write-Host ("        $Label : already running") -ForegroundColor DarkGray
        return
    }
    $args = @(
        '-NoExit'
        '-ExecutionPolicy','Bypass'
        '-File', "`"$Path`""
    )
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $args -WorkingDirectory $crestRoot -WindowStyle Minimized | Out-Null
        Write-Host ("        $Label : spawned (minimized)") -ForegroundColor Green
    } catch {
        Write-Host ("        $Label : spawn FAILED -- $($_.Exception.Message)") -ForegroundColor Red
    }
}

Write-Host ''
Write-Host '=========================================================' -ForegroundColor Cyan
Write-Host '  CREST Boot' -ForegroundColor Cyan
Write-Host '=========================================================' -ForegroundColor Cyan
Write-Host ''

# Step 1. Check watcher.
if (Test-WatcherAlive) {
    Write-Host '  [1/3] watcher is ALIVE (recent heartbeat)' -ForegroundColor Green
} else {
    Write-Host '  [1/3] watcher is NOT running -- spawning...' -ForegroundColor Yellow

    if (-not (Test-Path $watcherPath)) {
        Write-Host "        ERROR: $watcherPath not found." -ForegroundColor Red
        Write-Host '        Cannot start watcher. Aborting.' -ForegroundColor Red
        exit 1
    }

    # Spawn watcher in a new admin window so it persists independently.
    $args = @(
        '-NoExit'
        '-ExecutionPolicy','Bypass'
        '-File', "`"$watcherPath`""
    )
    try {
        if (Test-IsAdmin) {
            # Already admin: launch a sibling window directly.
            Start-Process -FilePath 'powershell.exe' -ArgumentList $args -WorkingDirectory $crestRoot | Out-Null
        } else {
            # Elevate.
            Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -WorkingDirectory $crestRoot | Out-Null
        }
        Write-Host '        spawn requested.' -ForegroundColor DarkGray
    } catch {
        Write-Host "        ERROR spawning watcher: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host '        You may need to start it manually:' -ForegroundColor Yellow
        Write-Host "          & $watcherPath" -ForegroundColor Yellow
        exit 1
    }

    # Step 2. Wait for first heartbeat (up to 30 s).
    Write-Host '  [2/3] waiting for watcher heartbeat...' -ForegroundColor Yellow
    $deadline = (Get-Date).AddSeconds(30)
    $alive    = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        if (Test-WatcherAlive) { $alive = $true; break }
        Write-Host '        ...' -ForegroundColor DarkGray
    }
    if ($alive) {
        Write-Host '        watcher is ALIVE.' -ForegroundColor Green
    } else {
        Write-Host '        watcher did not heartbeat within 30 s.' -ForegroundColor Yellow
        Write-Host '        Continuing anyway -- check the new window for errors.' -ForegroundColor Yellow
    }
}

# Step 2.5. Auxiliary daemons. Each handles a different self-healing duty.
# Watchdog restarts the main watcher if it dies. SourceWatch rebuilds CREST
# on any .cs save. DeployWatcher copies the new DLL when Bannerlord exits.
# All three should be running for the chain to be fully hands-free.
Write-Host '  [2.5/3] auxiliary daemons:'
Start-AuxDaemon -Path (Join-Path $crestRoot 'Crest-Watchdog.ps1')      -Label 'watchdog      '
Start-AuxDaemon -Path (Join-Path $crestRoot 'Crest-SourceWatch.ps1')   -Label 'source-watch  '
Start-AuxDaemon -Path (Join-Path $crestRoot 'Crest-DeployWatcher.ps1') -Label 'deploy-watcher'

# Step 2.6. Truncation guard. The em-dash bulk sweep historically truncated
# CrestBattleConvergence.cs. If source line count looks wildly short vs the
# decompiled snapshot, surface it loudly. Don't auto-mutate -- user is
# hands-off of CREST source by directive; just warn.
try {
    $convSrc = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\CrestBattleConvergence.cs'
    $convRecovered = Join-Path $crestRoot '.runner\diag\recovered\CrestBattleConvergence-recovered.cs'
    if ((Test-Path $convSrc) -and (Test-Path $convRecovered)) {
        $srcLines = (Get-Content $convSrc -ErrorAction SilentlyContinue).Count
        $recLines = (Get-Content $convRecovered -ErrorAction SilentlyContinue).Count
        if ($srcLines -lt ($recLines * 0.7)) {
            Write-Host ''
            Write-Host '  WARNING: CrestBattleConvergence.cs looks truncated' -ForegroundColor Yellow
            Write-Host ("    source     = $srcLines lines")                    -ForegroundColor Yellow
            Write-Host ("    decompiled = $recLines lines (from working DLL)") -ForegroundColor Yellow
            Write-Host '    deployed DLL is the canonical source of truth.'    -ForegroundColor DarkGray
            Write-Host '    To restore: copy the recovered file over the source.' -ForegroundColor DarkGray
        }
    }
} catch { }

# Step 3. Hand off to the unified entry, dispatching to the requested mode.
Write-Host "  [3/3] dispatching to Mode=$Mode..." -ForegroundColor Green
Write-Host ''
if (-not (Test-Path $entryPath)) {
    Write-Host "  ERROR: $entryPath not found." -ForegroundColor Red
    exit 1
}
if ($Arg) {
    & $entryPath -Mode $Mode -Arg $Arg
} else {
    & $entryPath -Mode $Mode
}