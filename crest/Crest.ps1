# =====================================================================
# Crest.ps1 -- unified CREST entry point.
# =====================================================================
# Single command, dispatches to subsystems by -Mode. Replaces the need
# to remember individual script names. The watcher (crest-dev.ps1) runs
# separately in its own admin PS window and is launched by Crest-Boot.ps1.
#
# Modes:
#   Postmortem     after-battle diagnostic (default if a battle was recent)
#   NewMod         smart mod-creation wizard (parses user description,
#                  asks only for missing fields)
#   Audit          codebase scan -> CODE_INDEX.md
#   Bisect         compare metrics across last 3 archived battles
#   Sim            run rule simulation against scenarios
#   Status         quick "where are we" snapshot
#   Menu           interactive mode picker (default if no -Mode given)
#
# Usage:
#   & C:\dev\bannerlord\crest\Crest.ps1                       (interactive menu)
#   & C:\dev\bannerlord\crest\Crest.ps1 -Mode Postmortem
#   & C:\dev\bannerlord\crest\Crest.ps1 -Mode NewMod
#   & C:\dev\bannerlord\crest\Crest.ps1 -Mode Audit
# =====================================================================

param(
    [ValidateSet('Ready','Postmortem','NewMod','ReviewDraft','Scaffold','Loop','Verbose','Record','Replay','DevMode','Audit','Bisect','Sim','Status','Menu','Cycle','SourceWatch','Watchdog','DeployWatcher','DriftCheck','AutoFix','Dashboard','AutoBattle','AutoCascade','FinalSim','VerifyOrBattle','Doctor','')]
    [string]$Mode = '',
    [string]$Arg  = ''     # generic argument, mode-specific meaning
)

$ErrorActionPreference = 'Continue'

$crestRoot   = 'C:\dev\bannerlord\crest'
$diagDir     = Join-Path $crestRoot '.runner\diag'
$eventsLog   = Join-Path $crestRoot '.runner\events.log'

# Watcher health probe: events.log heartbeat must be within last 90 sec.
function Test-WatcherAlive {
    if (-not (Test-Path $eventsLog)) { return $false }
    try {
        $last = Get-Content $eventsLog -Tail 1 -ErrorAction SilentlyContinue
        if ($last -match '^\[(.+)\]') {
            $ts = [DateTime]::Parse($Matches[1])
            return ((Get-Date) - $ts).TotalSeconds -lt 90
        }
    } catch { }
    return $false
}

function Show-Header {
    Write-Host ''
    Write-Host '=========================================================' -ForegroundColor Cyan
    Write-Host '  CREST -- Calradian Runtime Extensions & Standard Toolkit' -ForegroundColor Cyan
    Write-Host '=========================================================' -ForegroundColor Cyan
    if (Test-WatcherAlive) {
        Write-Host '  watcher: ALIVE' -ForegroundColor Green
    } else {
        Write-Host '  watcher: NOT RUNNING (run Crest-Boot.ps1 to start)' -ForegroundColor Yellow
    }
    Write-Host ''
}

# Helper: find PS daemons by script-name fragment + check staleness vs script mtime.
function Get-DaemonStalenessReasons {
    $reasons = @()

    # Map: script path  ->  label shown if stale.
    $daemons = @(
        @{ Path = 'C:\dev\bannerlord\crest\tools\crest-dev.ps1';      Label = 'main watcher (crest-dev.ps1)' }
        @{ Path = 'C:\dev\bannerlord\crest\Crest-SourceWatch.ps1';    Label = 'source watcher' }
        @{ Path = 'C:\dev\bannerlord\crest\Crest-Watchdog.ps1';       Label = 'watchdog' }
        @{ Path = 'C:\dev\bannerlord\crest\Crest-DeployWatcher.ps1';  Label = 'deploy watcher' }
    )

    try {
        $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -in 'powershell.exe','pwsh.exe' }
        foreach ($d in $daemons) {
            if (-not (Test-Path $d.Path)) { continue }
            $script = $d.Path
            $hits = $procs | Where-Object { $_.CommandLine -and $_.CommandLine.Contains((Split-Path -Leaf $script)) }
            foreach ($p in $hits) {
                try {
                    $start = [DateTime]::FromFileTime($p.CreationDate.ToFileTime())
                } catch {
                    # Win32_Process CreationDate is a CIM datetime; use the easier path
                    $start = $p.CreationDate
                }
                $mt = (Get-Item $script).LastWriteTime
                if ($mt -gt $start) {
                    $age = [int]($mt - $start).TotalSeconds
                    $reasons += ("$($d.Label) needs restart (script changed +${age}s ago)")
                }
            }
        }
    } catch { }

    # PS profile: compare $PROFILE mtime vs THIS session's start time.
    try {
        if (Test-Path $PROFILE) {
            $thisProc = Get-Process -Id $PID -ErrorAction SilentlyContinue
            if ($thisProc -and ((Get-Item $PROFILE).LastWriteTime -gt $thisProc.StartTime)) {
                $reasons += 'PS profile changed since this menu started (run: . $PROFILE)'
            }
        }
    } catch { }

    return $reasons
}

# Y.70: visible "ready for next battle" banner so the user always knows
# without having to inspect file state. Shown at the BOTTOM of the menu
# so it's the last thing on screen. Now also detects stale long-running
# processes whose script files have been edited since they started.
function Show-ReadyBanner {
    $crestModuleRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'
    $reasons = @()
    if (-not (Test-WatcherAlive))                                       { $reasons += 'watcher not running' }
    if (-not (Test-Path (Join-Path $crestModuleRoot 'record.on')))      { $reasons += 'record.on OFF (run Ready)' }
    if (Test-Path 'C:\dev\bannerlord\crest\.runner\deploy-pending.txt') { $reasons += 'pending deploy (close Bannerlord)' }
    try {
        $dev = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll'
        $dst = Join-Path $crestModuleRoot 'bin\Win64_Shipping_Client\Crest.Harmony.dll'
        if ((Test-Path $dev) -and (Test-Path $dst)) {
            $devSha = (Get-FileHash $dev -Algorithm SHA256).Hash.Substring(0,12)
            $dstSha = (Get-FileHash $dst -Algorithm SHA256).Hash.Substring(0,12)
            if ($devSha -ne $dstSha) { $reasons += "deployed DLL is stale ($dstSha != $devSha)" }
        }
    } catch { }

    # Bannerlord-running-with-stale-DLL: process StartTime vs deployed DLL mtime.
    try {
        $bl = Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue | Select-Object -First 1
        $dst = Join-Path $crestModuleRoot 'bin\Win64_Shipping_Client\Crest.Harmony.dll'
        if ($bl -and (Test-Path $dst)) {
            $dllMt = (Get-Item $dst).LastWriteTime
            if ($dllMt -gt $bl.StartTime) {
                $age = [int]($dllMt - $bl.StartTime).TotalSeconds
                $reasons += "Bannerlord running OLD DLL (deployed +${age}s after launch) -- restart Bannerlord"
            }
        }
    } catch { }

    # Long-running PS daemons + PS profile.
    $reasons += Get-DaemonStalenessReasons

    Write-Host ''
    if ($reasons.Count -eq 0) {
        Write-Host '  +-------------------------------------------------------+' -ForegroundColor Green
        Write-Host '  |                                                       |' -ForegroundColor Green
        Write-Host '  |              READY FOR NEXT BATTLE                    |' -ForegroundColor Green
        Write-Host '  |    Launch Bannerlord -- chain fires automatically     |' -ForegroundColor Green
        Write-Host '  |                                                       |' -ForegroundColor Green
        Write-Host '  +-------------------------------------------------------+' -ForegroundColor Green
    } else {
        Write-Host '  +-------------------------------------------------------+' -ForegroundColor Yellow
        Write-Host '  |              NOT READY FOR BATTLE                     |' -ForegroundColor Yellow
        foreach ($r in $reasons) {
            $line = '  |  - ' + $r
            if ($line.Length -gt 56) { $line = $line.Substring(0, 53) + '...' }
            Write-Host ($line.PadRight(57) + '|') -ForegroundColor Yellow
        }
        Write-Host '  +-------------------------------------------------------+' -ForegroundColor Yellow
    }
    Write-Host ''
}

function Show-Menu {
    Show-Header
    Write-Host '  Pick a mode:'
    Write-Host '    [R] Ready       -- BEFORE a battle (recorder on, log rotate)' -ForegroundColor Gray
    Write-Host '    [1] Postmortem  -- AFTER a battle (full diagnostic)' -ForegroundColor Gray
    Write-Host '    [2] NewMod      -- create a new mod with the wizard'  -ForegroundColor Gray
    Write-Host '    [3] Audit       -- scan source tree, build CODE_INDEX' -ForegroundColor Gray
    Write-Host '    [4] Bisect      -- compare last 3 archived battles' -ForegroundColor Gray
    Write-Host '    [5] Sim         -- run rule simulation' -ForegroundColor Gray
    Write-Host '    [6] Status      -- current project state' -ForegroundColor Gray
    Write-Host '    [7] Loop        -- build + sim gate (auto-iterate)' -ForegroundColor Gray
    Write-Host '    [8] Verbose     -- toggle rich rule logging' -ForegroundColor Gray
    Write-Host '    [9] Record      -- toggle battle recorder' -ForegroundColor Gray
    Write-Host '    [0] Replay      -- replay latest recording in sim' -ForegroundColor Gray
    Write-Host '    [D] DevMode     -- toggle auto-ready after every agent response' -ForegroundColor Gray
    Write-Host '    [Q] Quit' -ForegroundColor DarkGray
    Show-ReadyBanner
    $pick = Read-Host '  >'
    switch ($pick) {
        'r' { Invoke-Ready }
        'R' { Invoke-Ready }
        '1' { Invoke-Postmortem }
        '2' { Invoke-NewMod }
        '3' { Invoke-Audit }
        '4' { Invoke-Bisect }
        '5' { Invoke-Sim }
        '6' { Invoke-Status }
        '7' { Invoke-Loop }
        '8' { Invoke-Verbose }
        '9' { Invoke-Record }
        '0' { Invoke-Replay }
        'd' { Invoke-DevMode }
        'D' { Invoke-DevMode }
        'q' { exit 0 }
        'Q' { exit 0 }
        default { Write-Host '  unknown choice' -ForegroundColor Red; Show-Menu }
    }
}

function Invoke-Postmortem {
    Show-Header
    Write-Host '  --- Postmortem ---' -ForegroundColor Cyan
    & (Join-Path $crestRoot 'Crest-Postmortem.ps1')
}

function Invoke-Ready {
    Show-Header
    Write-Host '  --- Pre-Battle Ready ---' -ForegroundColor Cyan
    if ($Arg -ieq 'Verbose' -or $Arg -ieq 'WithVerbose') {
        & (Join-Path $crestRoot 'Crest-Ready.ps1') -WithVerbose
    } else {
        & (Join-Path $crestRoot 'Crest-Ready.ps1')
    }
}

function Invoke-NewMod {
    Show-Header
    Write-Host '  --- New Mod Wizard (Phase 4 -- coming next) ---' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  The smart wizard is in development. For now, here is the workflow:'
    Write-Host '    1. You describe the mod in detail (paste below).'
    Write-Host '    2. Your description is saved to .runner\mod-drafts\.'
    Write-Host '    3. The agent (Claude) reads the draft, identifies missing'
    Write-Host '       spec fields, and asks you for them in chat.'
    Write-Host '    4. Once spec is complete, scaffold + sim run automatically.'
    Write-Host ''
    Write-Host '  Type a name for this mod (PascalCase, e.g. WeatherSystem):'
    $name = Read-Host '  name'
    if (-not $name) { Write-Host '  cancelled' -ForegroundColor Yellow; return }

    Write-Host ''
    Write-Host '  Now describe what you want this mod to do, as detailed as you can.'
    Write-Host '  End with a single blank line.'
    Write-Host ''
    $desc = New-Object System.Text.StringBuilder
    while ($true) {
        $line = Read-Host '  >'
        if ([string]::IsNullOrWhiteSpace($line)) { break }
        [void]$desc.AppendLine($line)
    }

    $draftDir = Join-Path $crestRoot '.runner\mod-drafts'
    New-Item -ItemType Directory -Path $draftDir -Force | Out-Null
    $stamp     = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $draftPath = Join-Path $draftDir "$name-$stamp-draft.txt"
    $statusPath = Join-Path $draftDir "$name-$stamp-status.txt"

    Set-Content -Path $draftPath -Value @"
# Mod: $name
# Created: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))

## Description (raw user input)

$($desc.ToString())

## Spec status

PENDING_AGENT_REVIEW
"@ -Encoding utf8
    Set-Content -Path $statusPath -Value 'READY_FOR_AGENT_REVIEW' -Encoding utf8

    Write-Host ''
    Write-Host "  draft saved: $draftPath" -ForegroundColor Green
    Write-Host ''
    Write-Host '  --- Auto-review pass ---' -ForegroundColor Cyan
    & (Join-Path $crestRoot 'Crest-ReviewDraft.ps1') -DraftPath $draftPath
    Write-Host ''
    Write-Host '  TELL THE AGENT (Claude): "review the new mod draft"' -ForegroundColor Yellow
    Write-Host '  The agent will read the review JSON, ask only for the missing fields,'
    Write-Host '  then run Crest.ps1 -Mode Scaffold to build the module skeleton.' -ForegroundColor DarkGray
}

function Invoke-ReviewDraft {
    Show-Header
    Write-Host '  --- Review Draft ---' -ForegroundColor Cyan
    if ($Arg) {
        & (Join-Path $crestRoot 'Crest-ReviewDraft.ps1') -DraftPath $Arg
    } else {
        & (Join-Path $crestRoot 'Crest-ReviewDraft.ps1')
    }
}

function Invoke-Scaffold {
    Show-Header
    Write-Host '  --- Scaffold Mod ---' -ForegroundColor Cyan
    if (-not $Arg) {
        Write-Host '  ERROR: -Arg <path-to-spec.json> is required' -ForegroundColor Red
        Write-Host '  Usage: Crest.ps1 -Mode Scaffold -Arg .runner\mod-drafts\<Name>-<stamp>-spec.json' -ForegroundColor Yellow
        return
    }
    & (Join-Path $crestRoot 'Crest-Scaffold.ps1') -SpecPath $Arg
}

function Invoke-Loop {
    Show-Header
    Write-Host '  --- Iterate Loop (build + sim gate) ---' -ForegroundColor Cyan
    if ($Arg) {
        & (Join-Path $crestRoot 'Crest-Loop.ps1') -CsprojPath $Arg
    } else {
        & (Join-Path $crestRoot 'Crest-Loop.ps1')
    }
}

# ---------------------------------------------------------------------
# Y.70 Phase 6/7: verbose logging + battle replay capture toggles.
# Sentinel files live in the deployed CREST module folder so the live
# game can pick up the change within ~2 sec without a reload.
# ---------------------------------------------------------------------
$crestModuleRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'

function Set-CrestSentinel {
    param(
        [Parameter(Mandatory=$true)][string]$Name,    # 'verbose' or 'record'
        [Parameter(Mandatory=$true)][string]$State    # 'On' or 'Off'
    )
    if (-not (Test-Path $crestModuleRoot)) {
        Write-Host "  ERROR: CREST module folder not found at $crestModuleRoot" -ForegroundColor Red
        Write-Host '  Deploy CREST first (Crest-Postmortem will do it on the next cycle).' -ForegroundColor Yellow
        return $false
    }
    $sentinel = Join-Path $crestModuleRoot ("$Name.on")
    if ($State -ieq 'On') {
        Set-Content -Path $sentinel -Value ((Get-Date).ToString('o')) -Encoding utf8
        Write-Host "  $Name : ON  ($sentinel)" -ForegroundColor Green
    } elseif ($State -ieq 'Off') {
        if (Test-Path $sentinel) {
            Remove-Item $sentinel -Force -ErrorAction SilentlyContinue
            Write-Host "  $Name : OFF (sentinel removed)" -ForegroundColor Yellow
        } else {
            Write-Host "  $Name : already OFF" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  ERROR: -Arg must be On or Off (got: $State)" -ForegroundColor Red
        return $false
    }
    return $true
}

function Invoke-Verbose {
    Show-Header
    Write-Host '  --- Verbose logging toggle ---' -ForegroundColor Cyan
    if (-not $Arg) {
        $sentinel = Join-Path $crestModuleRoot 'verbose.on'
        $state = if (Test-Path $sentinel) { 'ON' } else { 'OFF' }
        Write-Host "  current state: $state" -ForegroundColor Gray
        Write-Host '  toggle with: Crest.ps1 -Mode Verbose -Arg On|Off' -ForegroundColor DarkGray
        return
    }
    [void](Set-CrestSentinel -Name 'verbose' -State $Arg)
}

function Invoke-Record {
    Show-Header
    Write-Host '  --- Battle recorder toggle ---' -ForegroundColor Cyan
    if (-not $Arg) {
        $sentinel = Join-Path $crestModuleRoot 'record.on'
        $state = if (Test-Path $sentinel) { 'ON' } else { 'OFF' }
        Write-Host "  current state: $state" -ForegroundColor Gray
        Write-Host '  toggle with: Crest.ps1 -Mode Record -Arg On|Off' -ForegroundColor DarkGray
        return
    }
    [void](Set-CrestSentinel -Name 'record' -State $Arg)
}

function Invoke-Replay {
    Show-Header
    Write-Host '  --- Replay archived battle ---' -ForegroundColor Cyan
    $jsonl = $Arg
    if (-not $jsonl) {
        if (Test-Path $crestModuleRoot) {
            $latest = Get-ChildItem $crestModuleRoot -Filter 'record-*.jsonl' -File -ErrorAction SilentlyContinue |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latest) { $jsonl = $latest.FullName }
        }
    }
    if (-not $jsonl -or -not (Test-Path $jsonl)) {
        Write-Host '  ERROR: no recording found.' -ForegroundColor Red
        return
    }
    $simCsproj = 'C:\dev\bannerlord\Bannerlord.Harmony\sim\Crest.Harmony.Sim\Crest.Harmony.Sim.csproj'
    & dotnet run --project $simCsproj --no-restore -- --replay $jsonl
}

function Invoke-DevMode {
    Show-Header
    Write-Host '  --- Dev Mode ---' -ForegroundColor Cyan
    if ($Arg) {
        & (Join-Path $crestRoot 'Crest-DevMode.ps1') -State $Arg
    } else {
        & (Join-Path $crestRoot 'Crest-DevMode.ps1')
    }
}

function Invoke-Audit  { Show-Header; & (Join-Path $crestRoot 'Crest-Audit.ps1') }
function Invoke-Bisect {
    Show-Header
    Write-Host '  --- Bisect ---' -ForegroundColor Cyan
    if ($Arg) { & (Join-Path $crestRoot 'Crest-Bisect.ps1') -Metric $Arg }
    else      { & (Join-Path $crestRoot 'Crest-Bisect.ps1') }
}
function Invoke-Sim {
    Show-Header
    Write-Host '  --- Sim ---' -ForegroundColor Cyan
    if ($Arg) { & (Join-Path $crestRoot 'Crest-Sim.ps1') -Scenario $Arg -ShowLog }
    else      { & (Join-Path $crestRoot 'Crest-Sim.ps1') }
}
function Invoke-Status {
    Show-Header
    Write-Host '  --- Project Status ---' -ForegroundColor Cyan
    Write-Host ''
    $dll = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client\Crest.Harmony.dll'
    if (Test-Path $dll) {
        $f = Get-Item $dll
        $h = (Get-FileHash $dll -Algorithm SHA256).Hash.Substring(0,12)
        Write-Host "  Crest.Harmony.dll: $($f.Length) bytes  sha=$h  $($f.LastWriteTime)" -ForegroundColor Green
    } else {
        Write-Host '  Crest.Harmony.dll: MISSING -- not deployed' -ForegroundColor Red
    }
    $arch = Join-Path $crestRoot '.runner\diag\battles'
    if (Test-Path $arch) {
        $bs = (Get-ChildItem $arch -Directory -Filter 'battle-*' -ErrorAction SilentlyContinue).Count
        Write-Host "  archived battles:  $bs"
    }
    $idx = Join-Path $crestRoot 'CODE_INDEX.md'
    if (Test-Path $idx) {
        $age = (Get-Date) - (Get-Item $idx).LastWriteTime
        Write-Host ("  CODE_INDEX.md:     {0} hr old (Mode Audit refreshes)" -f [int]$age.TotalHours)
    } else {
        Write-Host '  CODE_INDEX.md:     missing -- run Mode Audit' -ForegroundColor Yellow
    }
    Write-Host ''
}

function Invoke-Cycle          { Show-Header; & (Join-Path $crestRoot 'Crest-Cycle.ps1') }
function Invoke-SourceWatch    { Show-Header; & (Join-Path $crestRoot 'Crest-SourceWatch.ps1') }
function Invoke-Watchdog       { Show-Header; & (Join-Path $crestRoot 'Crest-Watchdog.ps1') }
function Invoke-DeployWatcher  { Show-Header; & (Join-Path $crestRoot 'Crest-DeployWatcher.ps1') }
function Invoke-DriftCheck     { Show-Header; & (Join-Path $crestRoot 'Crest-DriftCheck.ps1') }
function Invoke-AutoFix        { Show-Header; & (Join-Path $crestRoot 'Crest-AutoFixCommon.ps1') }
function Invoke-Dashboard      { & (Join-Path $crestRoot 'Herald-Dashboard.ps1') }
function Invoke-AutoBattle     { Show-Header; & (Join-Path $crestRoot 'Crest-AutoBattle.ps1') }
function Invoke-AutoCascade {
    Show-Header
    if ($Arg) { & (Join-Path $crestRoot 'Crest-AutoCascade.ps1') -State $Arg }
    else      { & (Join-Path $crestRoot 'Crest-AutoCascade.ps1') }
}
function Invoke-FinalSim {
    Show-Header
    Write-Host '  --- FinalSim (synthetic battle suite) ---' -ForegroundColor Cyan
    if ($Arg -match '^\d+$') {
        & (Join-Path $crestRoot 'Crest-FinalSim.ps1') -N ([int]$Arg)
    } else {
        & (Join-Path $crestRoot 'Crest-FinalSim.ps1')
    }
}
function Invoke-VerifyOrBattle {
    Show-Header
    Write-Host '  --- VerifyOrBattle (FinalSim then maybe AutoBattle) ---' -ForegroundColor Cyan
    if ($Arg -match '^\d+$') {
        & (Join-Path $crestRoot 'Crest-VerifyOrBattle.ps1') -N ([int]$Arg)
    } else {
        & (Join-Path $crestRoot 'Crest-VerifyOrBattle.ps1')
    }
}

function Show-Menu {
    Show-Header
    Write-Host '  Pick a mode:'
    Write-Host '    [R] Ready       -- BEFORE a battle (recorder on, log rotate)' -ForegroundColor Gray
    Write-Host '    [1] Postmortem  -- AFTER a battle (full diagnostic)' -ForegroundColor Gray
    Write-Host '    [2] NewMod      -- create a new mod with the wizard'  -ForegroundColor Gray
    Write-Host '    [3] Audit       -- scan source tree, build CODE_INDEX' -ForegroundColor Gray
    Write-Host '    [4] Bisect      -- compare last 3 archived battles' -ForegroundColor Gray
    Write-Host '    [5] Sim         -- run rule simulation' -ForegroundColor Gray
    Write-Host '    [6] Status      -- current project state' -ForegroundColor Gray
    Write-Host '    [7] Loop        -- build + sim gate (auto-iterate)' -ForegroundColor Gray
    Write-Host '    [8] Verbose     -- toggle rich rule logging' -ForegroundColor Gray
    Write-Host '    [9] Record      -- toggle battle recorder' -ForegroundColor Gray
    Write-Host '    [0] Replay      -- replay latest recording in sim' -ForegroundColor Gray
    Write-Host '    [D] DevMode     -- toggle auto-ready after every agent response' -ForegroundColor Gray
    Write-Host '    [G] Dashboard   -- open HERALD GUI' -ForegroundColor Gray
    Write-Host '    [F] FinalSim    -- replay last N battles, gate smoke test' -ForegroundColor Gray
    Write-Host '    [B] AutoBattle  -- launch + run + close (hands-free)' -ForegroundColor Gray
    Write-Host '    [Q] Quit' -ForegroundColor DarkGray
    Show-ReadyBanner
    $pick = Read-Host '  >'
    switch ($pick) {
        'r' { Invoke-Ready }
        'R' { Invoke-Ready }
        '1' { Invoke-Postmortem }
        '2' { Invoke-NewMod }
        '3' { Invoke-Audit }
        '4' { Invoke-Bisect }
        '5' { Invoke-Sim }
        '6' { Invoke-Status }
        '7' { Invoke-Loop }
        '8' { Invoke-Verbose }
        '9' { Invoke-Record }
        '0' { Invoke-Replay }
        'd' { Invoke-DevMode }
        'D' { Invoke-DevMode }
        'g' { Invoke-Dashboard }
        'G' { Invoke-Dashboard }
        'f' { Invoke-FinalSim }
        'F' { Invoke-FinalSim }
        'b' { Invoke-AutoBattle }
        'B' { Invoke-AutoBattle }
        'q' { exit 0 }
        'Q' { exit 0 }
        default { Write-Host '  unknown choice' -ForegroundColor Red; Show-Menu }
    }
}

# Dispatch.
switch ($Mode) {
    'Ready'          { Invoke-Ready;          break }
    'Postmortem'     { Invoke-Postmortem;     break }
    'NewMod'         { Invoke-NewMod;         break }
    'ReviewDraft'    { Invoke-ReviewDraft;    break }
    'Scaffold'       { Invoke-Scaffold;       break }
    'Loop'           { Invoke-Loop;           break }
    'Verbose'        { Invoke-Verbose;        break }
    'Record'         { Invoke-Record;         break }
    'Replay'         { Invoke-Replay;         break }
    'DevMode'        { Invoke-DevMode;        break }
    'Cycle'          { Invoke-Cycle;          break }
    'SourceWatch'    { Invoke-SourceWatch;    break }
    'Watchdog'       { Invoke-Watchdog;       break }
    'DeployWatcher'  { Invoke-DeployWatcher;  break }
    'DriftCheck'     { Invoke-DriftCheck;     break }
    'AutoFix'        { Invoke-AutoFix;        break }
    'Dashboard'      { Invoke-Dashboard;      break }
    'AutoBattle'     { Invoke-AutoBattle;     break }
    'AutoCascade'    { Invoke-AutoCascade;    break }
    'FinalSim'       { Invoke-FinalSim;       break }
    'VerifyOrBattle' { Invoke-VerifyOrBattle; break }
    'Audit'          { Invoke-Audit;          break }
    'Bisect'         { Invoke-Bisect;         break }
    'Sim'            { Invoke-Sim;            break }
    'Status'         { Invoke-Status;         break }
    'Doctor'         { & 'C:\dev\bannerlord\crest\Crest-Doctor.ps1' -Apply $Arg; break }
    'Menu'           { Show-Menu;             break }
    default          { Show-Menu }
}