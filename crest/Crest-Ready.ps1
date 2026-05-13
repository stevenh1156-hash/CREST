# =====================================================================
# Crest-Ready.ps1 -- pre-battle reflex.
# =====================================================================
# Counterpart to Crest-Postmortem.ps1. Standing-order trigger: when the
# user says "ready" the agent submits this script to the watcher queue
# to prepare the system for a fresh battle. Postmortem (on "done")
# tears down the same state and archives whatever was captured.
#
# What it does:
#   1. Battle-start marker          (.runner\diag\battle-start.txt)
#   2. Stale crash artifact sweep   (so postmortem only sees this battle)
#   3. runtime.log rotation         (this battle starts with an empty log)
#   4. Deploy-staleness check       (warns if Modules\CREST DLL is older
#                                    than the dev tree's latest build)
#   5. Recorder ENABLED             (record.on sentinel in CREST module)
#   6. Optional verbose             (verbose.on sentinel, with -Verbose)
#
# Usage:
#   & C:\dev\bannerlord\crest\Crest-Ready.ps1
#   & C:\dev\bannerlord\crest\Crest-Ready.ps1 -WithVerbose   (also enable verbose.on)
#   & C:\dev\bannerlord\crest\Crest-Ready.ps1 -SkipRotate    (keep prior log)
# =====================================================================

# NOTE: do NOT add [CmdletBinding()] -- it auto-injects a -Verbose common
# parameter that collides with our own switch. Plain param() block only.
param(
    [switch]$WithVerbose,    # also enable runtime-verbose.log per-tick logging
    [switch]$SkipRotate,     # keep the existing runtime.log (default: rotate to runtime-prev.log)
    [switch]$SkipDeployCheck # skip DLL freshness check
)

$ErrorActionPreference = 'Continue'

$crestRoot       = 'C:\dev\bannerlord\crest'
$crestModuleRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'
$diagDir         = Join-Path $crestRoot '.runner\diag'
$battleStart     = Join-Path $diagDir 'battle-start.txt'
$runtimeLog      = Join-Path $crestModuleRoot 'runtime.log'
$verbosePath     = Join-Path $crestModuleRoot 'runtime-verbose.log'
$recordSentinel  = Join-Path $crestModuleRoot 'record.on'
$verboseSentinel = Join-Path $crestModuleRoot 'verbose.on'

# --- intro ---
$stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
Write-Host ''
Write-Host '=========================================================' -ForegroundColor Cyan
Write-Host "  CREST Ready  $stamp" -ForegroundColor Cyan
Write-Host '=========================================================' -ForegroundColor Cyan
Write-Host ''

if (-not (Test-Path $crestModuleRoot)) {
    Write-Host "  ERROR: deployed CREST module not found at $crestModuleRoot" -ForegroundColor Red
    Write-Host '         Run a deploy (Crest-Postmortem auto-deploys) before saying ready.' -ForegroundColor Yellow
    exit 1
}

# --- 1. battle-start marker ---
Write-Host '  [1/6] battle-start marker' -ForegroundColor Cyan
New-Item -ItemType Directory -Path $diagDir -Force | Out-Null
Set-Content -Path $battleStart -Value $stamp -Encoding utf8
Write-Host "        $battleStart" -ForegroundColor DarkGray

# --- 2. stale crash artifact sweep ---
Write-Host '  [2/6] sweep stale crash artifacts' -ForegroundColor Cyan
$crashSources = @(
    "$env:USERPROFILE\Documents\Mount and Blade II Bannerlord\crashes"
    "$crestModuleRoot\..\..\rgl_log.txt"
    "$env:LOCALAPPDATA\CrashDumps"
)
$preBattleSweep = Join-Path $diagDir ("crashes\pre-battle-" + (Get-Date).ToString('yyyyMMdd-HHmmss'))
$movedCount = 0
foreach ($src in $crashSources) {
    if (-not (Test-Path $src)) { continue }
    if (Test-Path $src -PathType Container) {
        $items = Get-ChildItem $src -File -ErrorAction SilentlyContinue
        foreach ($it in $items) {
            if (-not (Test-Path $preBattleSweep)) { New-Item -ItemType Directory -Path $preBattleSweep -Force | Out-Null }
            Move-Item -Path $it.FullName -Destination $preBattleSweep -Force -ErrorAction SilentlyContinue
            $movedCount++
        }
    } else {
        if (-not (Test-Path $preBattleSweep)) { New-Item -ItemType Directory -Path $preBattleSweep -Force | Out-Null }
        Copy-Item -Path $src -Destination $preBattleSweep -Force -ErrorAction SilentlyContinue
    }
}
if ($movedCount -gt 0) {
    Write-Host "        moved $movedCount stale crash file(s) to $preBattleSweep" -ForegroundColor DarkGray
} else {
    Write-Host '        no stale crash artifacts to sweep' -ForegroundColor DarkGray
}

# --- 3. runtime.log rotation ---
Write-Host '  [3/6] runtime.log rotation' -ForegroundColor Cyan
if ($SkipRotate) {
    Write-Host '        skipped (-SkipRotate)' -ForegroundColor DarkGray
} elseif (Test-Path $runtimeLog) {
    $prev = Join-Path $crestModuleRoot 'runtime-prev.log'
    try {
        Move-Item -Path $runtimeLog -Destination $prev -Force -ErrorAction Stop
        $sz = if (Test-Path $prev) { [int]((Get-Item $prev).Length / 1KB) } else { 0 }
        Write-Host "        rotated -> runtime-prev.log (${sz} KB)" -ForegroundColor DarkGray
    } catch {
        Write-Host "        could not rotate (file may be locked): $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host '        no runtime.log to rotate (clean slate)' -ForegroundColor DarkGray
}
# Also rotate verbose log if present (it would contain previous-battle data
# now that recorder is about to start fresh).
if ((-not $SkipRotate) -and (Test-Path $verbosePath)) {
    $prevV = Join-Path $crestModuleRoot 'runtime-verbose-prev.log'
    try { Move-Item -Path $verbosePath -Destination $prevV -Force -ErrorAction Stop } catch { }
}

# --- 4. deploy staleness check ---
Write-Host '  [4/6] deploy staleness check' -ForegroundColor Cyan
if ($SkipDeployCheck) {
    Write-Host '        skipped (-SkipDeployCheck)' -ForegroundColor DarkGray
} else {
    $devDll    = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll'
    $deployDll = Join-Path $crestModuleRoot 'bin\Win64_Shipping_Client\Crest.Harmony.dll'
    if ((Test-Path $devDll) -and (Test-Path $deployDll)) {
        $devHash    = (Get-FileHash $devDll    -Algorithm SHA256).Hash.Substring(0,12)
        $deployHash = (Get-FileHash $deployDll -Algorithm SHA256).Hash.Substring(0,12)
        $devStamp    = (Get-Item $devDll).LastWriteTime
        $deployStamp = (Get-Item $deployDll).LastWriteTime
        if ($devHash -eq $deployHash) {
            Write-Host "        deployed DLL matches dev build  sha=$deployHash  ($deployStamp)" -ForegroundColor Green
        } else {
            Write-Host '        WARN: deployed DLL does NOT match dev build' -ForegroundColor Yellow
            Write-Host "          dev:     sha=$devHash    $devStamp" -ForegroundColor Yellow
            Write-Host "          deploy:  sha=$deployHash $deployStamp" -ForegroundColor Yellow
            Write-Host '          run a deploy (Crest-Postmortem auto-deploys) before testing.' -ForegroundColor Yellow
        }
    } elseif (Test-Path $deployDll) {
        $deployHash = (Get-FileHash $deployDll -Algorithm SHA256).Hash.Substring(0,12)
        Write-Host "        no dev build to compare against  deploy=$deployHash" -ForegroundColor DarkGray
    } else {
        Write-Host '        WARN: no deployed DLL found' -ForegroundColor Yellow
    }
}

# --- 5. recorder ON ---
Write-Host '  [5/6] recorder ENABLED' -ForegroundColor Cyan
Set-Content -Path $recordSentinel -Value $stamp -Encoding utf8
Write-Host "        $recordSentinel" -ForegroundColor Green
Write-Host '        every Evaluate tick will append to record-<stamp>.jsonl' -ForegroundColor DarkGray

# --- 6. verbose (optional) ---
Write-Host '  [6/6] verbose logging' -ForegroundColor Cyan
if ($WithVerbose) {
    Set-Content -Path $verboseSentinel -Value $stamp -Encoding utf8
    Write-Host "        ENABLED  $verboseSentinel" -ForegroundColor Green
    Write-Host '        per-tick rule decisions will write to runtime-verbose.log' -ForegroundColor DarkGray
} else {
    if (Test-Path $verboseSentinel) {
        # Leave it as-is -- user may have turned it on manually for a longer
        # diagnostic window. Just report the state.
        Write-Host '        (already on, leaving alone)' -ForegroundColor DarkGray
    } else {
        Write-Host '        skipped (pass -WithVerbose to enable)' -ForegroundColor DarkGray
    }
}

Write-Host ''
Write-Host '  READY -- launch Bannerlord, fight your battle, then say "done".' -ForegroundColor Green
Write-Host '          The postmortem will archive the recording and turn record off.' -ForegroundColor DarkGray
Write-Host ''
exit 0
