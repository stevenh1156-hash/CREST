# =====================================================================
# Crest-Postmortem.ps1
# =====================================================================
# Runs after EVERY battle. Single command, full diagnostic coverage.
# This is the script the agent (Claude) submits to the queue every time
# the user says "done."
#
# What this does:
#   1. Crest-Diag.ps1            -- refresh battle-summary, map, trails, narrative
#   2. GetCrash.ps1              -- collect any crash artifacts (harmless if none)
#   3. Crest-Sim.ps1             -- regression check on Y.54+Y.56 rules
#   4. Inventory checks          -- terrain scan status, spot formation count,
#                                   override counts, captain leaks, BEW
#   5. Delta vs previous run     -- key metrics changed since last battle
#   6. Sim coverage audit        -- which code paths are NOT covered by sim,
#                                   suggested next scenarios to add
#
# Output goes to:
#   - host (visible to watcher transcript and agent via result.json stdout)
#   - C:\dev\bannerlord\crest\.runner\diag\postmortem.txt   (durable copy)
# =====================================================================

$ErrorActionPreference = 'Continue'

$diagDir       = 'C:\dev\bannerlord\crest\.runner\diag'
$summary       = Join-Path $diagDir 'battle-summary.txt'
$postmortemTxt = Join-Path $diagDir 'postmortem.txt'
$prevSnap      = Join-Path $diagDir 'previous-postmortem.txt'
$battlesDir    = Join-Path $diagDir 'battles'

# --- Multi-battle archival: rotate last 3 battle outputs ---
# Before refreshing diag, snapshot the CURRENT state to battles\<timestamp>\
# so the most recent N battles can be compared. Useful for cross-map
# comparison and auto-bisect (Crest-Bisect.ps1 walks these archives).
New-Item -ItemType Directory -Path $battlesDir -Force | Out-Null
if (Test-Path $summary) {
    $stamp   = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $archive = Join-Path $battlesDir "battle-$stamp"
    New-Item -ItemType Directory -Path $archive -Force | Out-Null
    foreach ($f in @(
        'battle-summary.txt', 'battle-narrative.md',
        'battle-map.png', 'battle-trails.png',
        'runtime.log', 'main-menu-messages.log',
        'postmortem.txt', 'previous-postmortem.txt',
        'latest-runtime-tail.log', 'latest-main-menu-tail.log'
    )) {
        $src = Join-Path $diagDir $f
        if (Test-Path $src) { Copy-Item $src (Join-Path $archive $f) -Force }
    }
    # Prune to last 3 archives.
    $existing = Get-ChildItem $battlesDir -Directory -Filter 'battle-*' |
                Sort-Object Name -Descending
    if ($existing.Count -gt 3) {
        $existing | Select-Object -Skip 3 | ForEach-Object {
            Remove-Item -Recurse -Force $_.FullName -ErrorAction SilentlyContinue
        }
    }
}

# Move the previous postmortem aside so we can compute delta.
if (Test-Path $postmortemTxt) {
    Copy-Item $postmortemTxt $prevSnap -Force
}
if (Test-Path $postmortemTxt) { Remove-Item $postmortemTxt -Force }

function PMLog($s, [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray) {
    if ($s -isnot [string]) { $s = ($s | Out-String).TrimEnd() }
    $s | Add-Content -Path $postmortemTxt -Encoding utf8
    Write-Host $s -ForegroundColor $Color
}

# --------------------------------------------------------------------
# Step 0 (FIRST PRIORITY): check for and surface any crash.
# A crash takes the lead in the postmortem -- everything else is
# secondary if the game just died. We need to know that BEFORE wading
# into rule overrides and scan results.
# --------------------------------------------------------------------
$prevPostmortemTime = $null
if (Test-Path $prevSnap) {
    try { $prevPostmortemTime = (Get-Item $prevSnap).LastWriteTime } catch { }
}
PMLog '== step 0: CRASH CHECK (always first) ==' Cyan
& C:\dev\bannerlord\crest\tools\diag\GetCrash.ps1 *>&1 | ForEach-Object { PMLog $_ DarkGray }

# Detect fresh crashes: any artifact in latest-* with mtime > previous postmortem.
$freshArtifacts = @()
$crashFiles = @(
    'latest-crash.html'
    'latest-crash-exception.txt'
    'latest-rgl_log.txt'
    'latest-rgl_log-tail.txt'
    'latest-tw-dump.txt'
)
foreach ($f in $crashFiles) {
    $p = Join-Path $diagDir $f
    if (-not (Test-Path $p)) { continue }
    $mtime = (Get-Item $p).LastWriteTime
    if ($prevPostmortemTime -eq $null -or $mtime -gt $prevPostmortemTime) {
        $freshArtifacts += $p
    }
}

if ($freshArtifacts.Count -gt 0) {
    PMLog ''
    PMLog '##############################################################' Red
    PMLog '##                                                          ##' Red
    PMLog '##   *** FRESH CRASH ARTIFACTS DETECTED -- INSPECT FIRST *** ##' Red
    PMLog '##                                                          ##' Red
    PMLog '##############################################################' Red
    PMLog ''
    foreach ($f in $freshArtifacts) {
        $info = Get-Item $f
        PMLog ("  {0,-40}  {1,8} bytes  modified {2}" -f $info.Name, $info.Length, $info.LastWriteTime) Yellow
    }
    # Inline preview of the exception text if we have it
    $excerpt = Join-Path $diagDir 'latest-crash-exception.txt'
    if (Test-Path $excerpt) {
        PMLog ''
        PMLog '  ----- exception excerpt (first 800 chars) -----' Yellow
        $body = Get-Content $excerpt -Raw -ErrorAction SilentlyContinue
        if ($body) { PMLog ('  ' + $body.Substring(0, [Math]::Min(800, $body.Length))) DarkYellow }
    }
    # Otherwise inline the rgl_log tail (engine log, our best signal on hard CTD)
    $rglTail = Join-Path $diagDir 'latest-rgl_log-tail.txt'
    if (-not (Test-Path $excerpt) -and (Test-Path $rglTail)) {
        PMLog ''
        PMLog '  ----- rgl_log tail (no managed exception = hard CTD) -----' Yellow
        Get-Content $rglTail -Tail 30 -ErrorAction SilentlyContinue | ForEach-Object { PMLog ('  ' + $_) DarkYellow }
    }
    PMLog ''
} else {
    PMLog '  no fresh crash artifacts since last postmortem' Green
}

# --------------------------------------------------------------------
# Step 1: refresh diag
# --------------------------------------------------------------------
PMLog ''
PMLog '== step 1: Crest-Diag.ps1 (refresh battle artifacts) ==' Cyan
& C:\dev\bannerlord\crest\Crest-Diag.ps1 *>&1 | ForEach-Object { PMLog $_ DarkGray }

# --------------------------------------------------------------------
# Step 3: sim regression
# --------------------------------------------------------------------
PMLog ''
PMLog '== step 3: Crest-Sim.ps1 (rule regression check) ==' Cyan
& C:\dev\bannerlord\crest\Crest-Sim.ps1 -NoBuild *>&1 | ForEach-Object { PMLog $_ DarkGray }
$simExit = $LASTEXITCODE

# --------------------------------------------------------------------
# Step 4: inventory checks
# --------------------------------------------------------------------
PMLog ''
PMLog '== step 4: postmortem inventory ==' Cyan
if (-not (Test-Path $summary)) {
    PMLog '  battle-summary.txt missing -- skipping inventory' Red
} else {
    # Terrain scan status
    $ringFallback = Select-String -Path $summary -Pattern 'RING-FALLBACK' -Quiet
    if ($ringFallback) {
        PMLog '  scan:           RING FALLBACK (terrain scan failed or flat map)' Yellow
    } else {
        $scanLine = Select-String -Path $summary -Pattern 'Y\.59 terrain-scan' | Select-Object -First 1
        if ($scanLine) {
            $tail = $scanLine.Line.Substring($scanLine.Line.IndexOf('Y.59'))
            PMLog "  scan:           $tail" Green
        } else {
            PMLog '  scan:           NO Y.59 LINE (scan never ran?)' Red
        }
    }

    # Y.65 structure probe (Y.70 Phase A target)
    $y65Probe = Select-String -Path $summary -Pattern 'Y\.65 (probe|walk):' -ErrorAction SilentlyContinue | Select-Object -First 2
    if ($y65Probe) {
        foreach ($p in $y65Probe) {
            $tail = $p.Line.Substring($p.Line.IndexOf('Y.65'))
            $color = if ($tail -match 'structures-found=[1-9]|structures matched.+[1-9]') { 'Green' } else { 'Yellow' }
            PMLog "  structures:     $tail" $color
        }
    } else {
        PMLog '  structures:     no Y.65 probe line (build pre-Y.70 or scan failed)' DarkGray
    }

    # Spot formations
    $spotForms = (Select-String -Path $summary -Pattern 'Y\.60a spot-formation').Count
    if ($spotForms -gt 0) {
        PMLog "  spot formations: $spotForms created (Y.60a)" Green
    } else {
        PMLog '  spot formations: NONE (Y.60a did not run?)' Red
    }

    # Spot occupancy -- did Y.60b actually route agents to spots?
    $spotOccupied = (Select-String -Path $summary -Pattern 'Y\.60c \[' -ErrorAction SilentlyContinue).Count
    if ($spotOccupied -gt 0) {
        PMLog "  spot occupancy:  $spotOccupied diag lines (Y.60b routing CONFIRMED firing)" Green
    } else {
        PMLog '  spot occupancy:  NONE -- Y.60b routing may not be firing' Yellow
    }

    # Y.60d spot orders -- did per-spot tier/variant logic run?
    $spotOrders = (Select-String -Path $summary -Pattern 'Y\.60d spot-orders' -ErrorAction SilentlyContinue).Count
    if ($spotOrders -gt 0) {
        PMLog "  spot orders:     $spotOrders applied (Y.60d tier/variant active)" Green
    } else {
        PMLog '  spot orders:     0 (Y.60d not firing -- no spots filled?)' Yellow
    }

    # Pool tier transitions (legacy path -- should be 0 once Y.60b drops pool routing)
    $poolTier = (Select-String -Path $summary -Pattern 'Y\.30B: pool tier').Count
    if ($poolTier -gt 0) {
        PMLog "  pool tier txns:  $poolTier (legacy pool path active)"
    } else {
        PMLog '  pool tier txns:  0 (Y.60b bypassed pool routing -- expected)' Green
    }

    # Y.54 overrides
    $cav   = (Select-String -Path $summary -Pattern 'Y\.54 override.*cav-unstuck').Count
    $brk   = (Select-String -Path $summary -Pattern 'Y\.54 override.*broken-retreat').Count
    $wand  = (Select-String -Path $summary -Pattern 'Y\.54 override.*wander-clamp').Count
    $clr   = (Select-String -Path $summary -Pattern 'Y\.56 clear').Count
    PMLog "  overrides:       cav-unstuck=$cav broken-retreat=$brk wander-clamp=$wand clears=$clr"

    # Captain leaks (units > 0 with captain=null in same Y.42 line)
    $capLeaks = Select-String -Path $summary -Pattern 'units=\d+.*captain=null'
    if ($capLeaks.Count -gt 0) {
        PMLog "  captain leaks:   $($capLeaks.Count) (Y.53 should fix on next cycle)" Yellow
    } else {
        PMLog '  captain leaks:   none' Green
    }

    # BEW exceptions
    $bew = Select-String -Path $summary -Pattern '\[BEW\]'
    if ($bew.Count -gt 0) {
        PMLog "  BEW exceptions:  $($bew.Count) -- INSPECT BELOW" Red
        $bew | Select-Object -First 5 | ForEach-Object { PMLog "    $($_.Line)" Yellow }
    } else {
        PMLog '  BEW exceptions:  none' Green
    }

    # Caught/swallowed exceptions
    $caught = (Select-String -Path $summary -Pattern 'caught in|MBException|Exception:').Count
    if ($caught -gt 0) {
        PMLog "  caught excs:     $caught"
    } else {
        PMLog '  caught excs:     none' Green
    }

    # Pool fallback fires (Y.60b spawn pump should rarely hit this)
    $poolFb = (Select-String -Path $summary -Pattern 'pool fallback|pool path').Count
    PMLog "  pool fallback:   $poolFb fires"
}

# --------------------------------------------------------------------
# Step 5: delta vs previous postmortem (if any)
# --------------------------------------------------------------------
PMLog ''
PMLog '== step 5: delta vs previous run ==' Cyan
if (Test-Path $prevSnap) {
    # Compare a few key metric lines.
    $keys = @(
        'overrides:       ', 'captain leaks:   ', 'BEW exceptions:  ',
        'pool tier txns:  ', 'spot formations:'
    )
    foreach ($k in $keys) {
        $cur  = (Select-String -Path $postmortemTxt -SimpleMatch $k -ErrorAction SilentlyContinue | Select-Object -First 1).Line
        $prv  = (Select-String -Path $prevSnap      -SimpleMatch $k -ErrorAction SilentlyContinue | Select-Object -First 1).Line
        if ($cur -and $prv -and $cur -ne $prv) {
            PMLog ("  CHANGED  was: $prv") Yellow
            PMLog ("           now: $cur") Yellow
        } elseif ($cur) {
            PMLog ("  same     $cur")
        }
    }
} else {
    PMLog '  (no previous postmortem to compare against)' DarkGray
}

# --------------------------------------------------------------------
# Step 6: sim coverage audit -- always remind the agent what's NOT tested
# --------------------------------------------------------------------
PMLog ''
PMLog '== step 6: sim coverage audit (could it be improved?) ==' Cyan
PMLog '  COVERED (5 scenarios):'
PMLog '    01-wandering-archers           Y.54 wander-clamp threshold + Y.56 sticky'
PMLog '    02-cav-stuck-in-shieldwall     Y.54 cav-unstuck'
PMLog '    03-broken-retreat              Y.54 broken-retreat threshold'
PMLog '    04-healthy-baseline            negative test (no false fires)'
PMLog '    05-stranded-archers            Y.58 anchorD>50 boundary'
PMLog ''
PMLog '  NOT COVERED (gaps the agent should consider filling):'
PMLog '    Y.53 captain re-elect          decide which agent to elect when first one dies'
PMLog '    Y.55 BEW mirror                exception type/message logging path'
PMLog '    Y.59 terrain scan              hill detection on synthetic heightmap'
PMLog '    Y.60a spot formation creation  team/slot allocation success'
PMLog '    Y.60b PickSpotForAgent         class-aware fill + capacity overflow + pool fallback'
PMLog '    Y.42 diag emission             does diag log every formation? captain reads work?'
PMLog '    Multi-pool/multi-spot          invariants across pool[i] interactions'
PMLog ''
PMLog '  IF SIMS PASS BUT REAL BATTLE BREAKS, THIS LIST IS WHERE TO LOOK FIRST.'

# --------------------------------------------------------------------
# Step 6.5: cross-battle delta (last 3 battles).
# Compares key metrics across the archived battles to show trends.
# --------------------------------------------------------------------
PMLog ''
PMLog '== step 6.5: cross-battle trends (last 3 battles) ==' Cyan
$archives = Get-ChildItem $battlesDir -Directory -Filter 'battle-*' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 3
if ($archives -and $archives.Count -ge 1) {
    PMLog "  archived battles: $($archives.Count)"
    $i = 1
    foreach ($a in $archives) {
        $pmFile = Join-Path $a.FullName 'postmortem.txt'
        if (-not (Test-Path $pmFile)) { continue }
        $line = (Select-String -Path $pmFile -Pattern '^\s*overrides:' -ErrorAction SilentlyContinue | Select-Object -First 1).Line
        $occ  = (Select-String -Path $pmFile -Pattern '^\s*spot occupancy:' -ErrorAction SilentlyContinue | Select-Object -First 1).Line
        PMLog "  battle-$i ($($a.Name)):"
        if ($line) { PMLog "    $($line.Trim())" }
        if ($occ)  { PMLog "    $($occ.Trim())" }
        $i++
    }
} else {
    PMLog '  (no archived battles yet -- archive starts after this run)'
}
PMLog ''
PMLog '  Run battles on DIFFERENT MAPS to maximize coverage:'
PMLog '    - flat plains   (forces ring-fallback path in Y.59 scan)'
PMLog '    - mountainous   (current map -- 181m elevation)'
PMLog '    - forest        (terrain affects spot placement, future Y.65 houses-aware)'
PMLog '    - village/town  (structures + chokepoints, Y.65/Y.67)'
PMLog '    - small army    (stress capacity gates, fewer lords)'
PMLog '    - large army    (stress per-call cap, queue overflow)'

# --------------------------------------------------------------------
# Step 7: commit / document checklist.
# After every postmortem the agent reviews whether changes from this
# session need to flow to other parts of the project. This is a
# REMINDER -- the agent answers each item explicitly in their reply.
# --------------------------------------------------------------------
PMLog ''
PMLog '== step 7: commit / document checklist (agent must answer each) ==' Cyan
PMLog '  After this postmortem, review whether changes need to flow to:'
PMLog ''
PMLog '  [ ] CREST module presets (CrestSettings.cs defaults / preset profiles)'
PMLog '      -- did we change a default that should be in Default/Cinema/etc preset?'
PMLog ''
PMLog '  [ ] Sim coverage (Crest.Harmony.Sim/scenarios/*.json)'
PMLog '      -- did we ship a new rule or threshold without sim coverage?'
PMLog '      -- the sim audit above lists what is NOT covered'
PMLog ''
PMLog '  [ ] Crest-Diag.ps1 (battle-summary sections + narrative emoji)'
PMLog '      -- does the diag surface any new log line we just shipped?'
PMLog ''
PMLog '  [ ] Bannerlord module creator (tools\Crest-NewMod.ps1 + scaffolding)'
PMLog '      -- did we change a CREST API surface that consumer mods reference?'
PMLog ''
PMLog '  [ ] START.md (project bootstrap doc for next AI session)'
PMLog '      -- does Section 2 "where we are RIGHT NOW" need a refresh?'
PMLog '      -- did we add or change a workflow rule?'
PMLog ''
PMLog '  [ ] Crest-Postmortem.ps1 itself (this file)'
PMLog '      -- did we ship a new diagnostic that should be auto-checked?'
PMLog ''
PMLog '  Agent: explicitly call out which boxes apply this session.'

# --------------------------------------------------------------------
# Step 7.5: Y.70 sentinel hygiene + recording archive
# --------------------------------------------------------------------
# Counterpart to Crest-Ready.ps1. If the user said "ready" before this
# battle, record.on (and possibly verbose.on) are sitting in the CREST
# module folder along with a fresh record-*.jsonl. Archive the recording
# next to this battle's diag bundle, then turn the sentinels off so
# disk doesn't keep filling between sessions.
PMLog ''
PMLog '== step 7.5: Y.70 sentinel hygiene + recording archive ==' Cyan
$crestModuleRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'
$verboseSentinel = Join-Path $crestModuleRoot 'verbose.on'
$recordSentinel  = Join-Path $crestModuleRoot 'record.on'

# --- Archive the most recent recording, if any -----------------------
# Also archives the matching record-geometry-*.jsonl (Y.73) so FinalSim
# can replay positions + terrain alongside the rule-evaluation ticks.
$archivedPath = $null
if (Test-Path $crestModuleRoot) {
    $recs = Get-ChildItem $crestModuleRoot -Filter 'record-*.jsonl' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike 'record-geometry-*' }
    if ($recs) {
        $latest = $recs | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $battlesDir = 'C:\dev\bannerlord\crest\.runner\diag\battles'
        if (Test-Path $battlesDir) {
            $archive = Get-ChildItem $battlesDir -Directory -Filter 'battle-*' -ErrorAction SilentlyContinue |
                       Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($archive) {
                $archivedPath = Join-Path $archive.FullName 'record.jsonl'
                try {
                    Copy-Item $latest.FullName -Destination $archivedPath -Force
                    $kb = [int]($latest.Length / 1KB)
                    PMLog "  recording archived -> battles\$($archive.Name)\record.jsonl  (${kb} KB)" Green
                    PMLog "    replay later: Crest.ps1 -Mode Replay -Arg `"$archivedPath`"" DarkGray
                } catch {
                    PMLog "  WARN: could not copy recording: $($_.Exception.Message)" Yellow
                }
                # Also archive the freshest geometry recording, if present.
                $geom = Get-ChildItem $crestModuleRoot -Filter 'record-geometry-*.jsonl' -File -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($geom) {
                    $geomDest = Join-Path $archive.FullName 'record-geometry.jsonl'
                    try {
                        Copy-Item $geom.FullName -Destination $geomDest -Force
                        $gkb = [int]($geom.Length / 1KB)
                        PMLog "  geometry archived  -> battles\$($archive.Name)\record-geometry.jsonl  (${gkb} KB)" Green
                    } catch {
                        PMLog "  WARN: could not copy geometry: $($_.Exception.Message)" Yellow
                    }
                } else {
                    PMLog '  no record-geometry-*.jsonl yet (Y.73 build pending)' DarkGray
                }
            } else {
                PMLog '  no battle-* archive folder found -- recording left in module root' DarkGray
            }
        }
    } else {
        PMLog '  no record-*.jsonl in module folder (recorder was off this battle)' DarkGray
    }
}

# --- Sentinel hygiene (per Y.70 design: leave record.on ON during dev) ---
# During module-creator iteration we leave record.on enabled across
# postmortems so every battle is captured automatically. Crest-Ready
# reasserts it anyway; clearing it here just churns I/O.
# Verbose still gets cleared because it grows runtime-verbose.log fast.
if (Test-Path $recordSentinel) {
    PMLog '  record:   ON (left enabled for dev-mode capture)' DarkGray
} else {
    PMLog '  record:   off (will be re-enabled by next Crest-Ready)' DarkGray
}
if (Test-Path $verboseSentinel) {
    $verboseLog = Join-Path $crestModuleRoot 'runtime-verbose.log'
    $vKb = if (Test-Path $verboseLog) { [int]((Get-Item $verboseLog).Length / 1KB) } else { 0 }
    Remove-Item $verboseSentinel -Force -ErrorAction SilentlyContinue
    PMLog "  verbose:  DISABLED (sentinel removed; runtime-verbose.log was ${vKb} KB)" Yellow
} else {
    PMLog '  verbose:  off' DarkGray
}

# --- Sweep stale module-root recordings older than 24h --------------
# (One battle per session is the norm; older files are clutter.)
if (Test-Path $crestModuleRoot) {
    $cutoff = (Get-Date).AddHours(-24)
    $stale  = Get-ChildItem $crestModuleRoot -Filter 'record-*.jsonl' -File -ErrorAction SilentlyContinue |
              Where-Object { $_.LastWriteTime -lt $cutoff }
    if ($stale) {
        $totKb = [int](( $stale | Measure-Object -Property Length -Sum ).Sum / 1KB)
        foreach ($f in $stale) { Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue }
        PMLog "  cleanup:  removed $($stale.Count) stale recording(s) (${totKb} KB)" DarkGray
    }
}

# --------------------------------------------------------------------
# Final summary
# --------------------------------------------------------------------
PMLog ''
# --------------------------------------------------------------------
# Token-efficient digest: tiny file the agent can read in 5 lines instead
# of slurping the whole 50KB postmortem JSON. Section 0.2 auto-detect
# rule should prefer this. Format is stable so a regex/string compare
# off the digest tells the agent whether anything's interesting.
# --------------------------------------------------------------------
$digestPath = 'C:\dev\bannerlord\crest\.runner\diag\postmortem-digest.txt'
$digestLines = @()

# Sim status (PASS/FAIL).
$digestLines += 'sim=' + $(if ($simExit -eq 0) { 'PASS' } else { "FAIL($simExit)" })

# Crash flag. The canonical signal is the diag\crashes\<stamp>\ bundle
# that GetCrash.ps1 writes at the top of every postmortem. We classify
# based on what GetCrash actually found:
#   YES if the most recent (non pre-battle-*) bundle has any of:
#     - crashreport*.html (BUTR managed report)
#     - rgl_log*.txt or rgl_log-tail.txt (engine log on hard CTD)
#     - dump_*.txt (TaleWorlds native dump)
#     - crash-exception.txt (BUTR excerpt)
#     - runtime-tail.log containing crash keywords
# Plus two fall-through signals kept for safety:
#   - $env:CREST_LAST_CRASH_BUNDLE set by the watcher when it auto-queued
#     this postmortem from a crash bundle detection
#   - $env:CREST_LAST_CRASH (legacy) for manual invocations
$crashFlag = 'no'
$crashReportPath = ''
$crashSignals = @()
try {
    # 1. Env vars set by the watcher when it queued this run.
    if ($env:CREST_LAST_CRASH_BUNDLE -and (Test-Path $env:CREST_LAST_CRASH_BUNDLE)) {
        $crashFlag = 'YES'; $crashReportPath = $env:CREST_LAST_CRASH_BUNDLE; $crashSignals += 'env:bundle'
    }
    if ($env:CREST_LAST_CRASH -and (Test-Path $env:CREST_LAST_CRASH)) {
        $crashFlag = 'YES'; if (-not $crashReportPath) { $crashReportPath = $env:CREST_LAST_CRASH }; $crashSignals += 'env:html'
    }

    # 2. Inspect the most recent diag\crashes\<stamp>\ bundle that isn't
    #    a pre-battle sweep. (GetCrash.ps1 just wrote one in step 2 above.)
    $bundleRoot = 'C:\dev\bannerlord\crest\.runner\diag\crashes'
    if (Test-Path $bundleRoot) {
        $latestBundle = Get-ChildItem $bundleRoot -Directory -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -notlike 'pre-battle-*' } |
                        Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latestBundle) {
            if (-not $crashReportPath) { $crashReportPath = $latestBundle.FullName }
            if (Get-ChildItem $latestBundle.FullName -Filter 'crashreport*.html' -File -ErrorAction SilentlyContinue) {
                $crashFlag = 'YES'; $crashSignals += 'BUTR-html'
            }
            if (Get-ChildItem $latestBundle.FullName -Filter 'rgl_log*.txt' -File -ErrorAction SilentlyContinue) {
                $crashFlag = 'YES'; $crashSignals += 'rgl_log'
            }
            if (Get-ChildItem $latestBundle.FullName -Filter 'dump_*.txt' -File -ErrorAction SilentlyContinue) {
                $crashFlag = 'YES'; $crashSignals += 'tw-dump'
            }
            if (Test-Path (Join-Path $latestBundle.FullName 'crash-exception.txt')) {
                $crashFlag = 'YES'; $crashSignals += 'crash-exception'
            }
            $rt = Join-Path $latestBundle.FullName 'runtime-tail.log'
            if ((Test-Path $rt) -and ($crashFlag -ne 'YES')) {
                $tail = Get-Content $rt -Tail 80 -ErrorAction SilentlyContinue
                if ($tail -match '(?i)\b(fatal|exception|stack trace|unhandled|access violation|nullref)\b') {
                    $crashFlag = 'YES'; $crashSignals += 'runtime-keywords'
                }
            }
        }
    }
} catch { }
$digestLines += 'crash=' + $crashFlag
if ($crashSignals.Count -gt 0) { $digestLines += 'crash_signals=' + ($crashSignals -join ',') }
if ($crashReportPath) { $digestLines += 'crashreport=' + $crashReportPath }

# Latest inventory line for at-a-glance metrics.
if (Test-Path $summary) {
    $invLine = Select-String -Path $summary -Pattern 'wander-clamp=\d+ clears=\d+' | Select-Object -First 1
    if ($invLine) { $digestLines += 'overrides=' + ($invLine.Line -replace '.*overrides:\s+','') }
    $y65 = Select-String -Path $summary -Pattern 'Y\.65 (probe|walk):' | Select-Object -First 1
    if ($y65) { $digestLines += 'structures=' + ($y65.Line.Substring($y65.Line.IndexOf('Y.65'))) }
}

# Delta summary.
$deltaCount = if (Test-Path $postmortemTxt) {
    (Select-String -Path $postmortemTxt -Pattern '^\s*CHANGED' -ErrorAction SilentlyContinue).Count
} else { 0 }
$digestLines += "delta-changed=$deltaCount"

# Stamp + interesting flag — agent reads this and decides whether to elaborate.
# Y.71+ expanded stats. Pull from runtime-prev (last battle) since
# Crest-Ready already rotated the live runtime.log. Falls back to live
# log if prev is missing.
try {
    $logForStats = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\runtime-prev.log'
    if (-not (Test-Path $logForStats)) {
        $logForStats = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\runtime.log'
    }
    if (Test-Path $logForStats) {
        $overrideCount = (Select-String -Path $logForStats -Pattern 'Y\.54 override:' -ErrorAction SilentlyContinue).Count
        $digestLines += "overrides=$overrideCount"
        $routedTotal = 0; $unitsTotal = 0
        foreach ($l in (Select-String -Path $logForStats -Pattern 'Y\.60c.*routed=(\d+)\s+units=(\d+)' -ErrorAction SilentlyContinue)) {
            $r = [int]$l.Matches[0].Groups[1].Value
            $u = [int]$l.Matches[0].Groups[2].Value
            $routedTotal += $r; $unitsTotal += $u
        }
        if ($routedTotal -gt 0) {
            $acc = [int](100.0 * $unitsTotal / $routedTotal)
            $digestLines += "routing_accuracy=${acc}%"
        }
    }
} catch { }

$digestLines += 'stamp=' + (Get-Date).ToString('o')
$interesting = ($simExit -ne 0) -or ($crashFlag -eq 'YES') -or ($deltaCount -gt 2)
$digestLines += 'interesting=' + $(if ($interesting) { 'yes' } else { 'no' })

# FinalSim verdict (synthetic battle replay suite). Stamped here so the
# agent and HERALD can decide if a real in-game smoke test is needed.
$finalSimVerdict = 'unknown'
$finalSimVerdictPath = 'C:\dev\bannerlord\crest\.runner\diag\finalsim-verdict.txt'
if (Test-Path $finalSimVerdictPath) {
    try { $finalSimVerdict = (Get-Content $finalSimVerdictPath -Raw -ErrorAction SilentlyContinue).Trim() } catch { }
}
$digestLines += "finalsim=$finalSimVerdict"

# Verdict: one-word interpretation. Agent reads this first; everything
# else can be skipped on a green verdict (verdict=stable + interesting=no).
$verdict = 'stable'
if ($crashFlag -eq 'YES')   { $verdict = 'crashed' }
elseif ($simExit -ne 0)     { $verdict = 'sim-regression' }
elseif ($deltaCount -gt 5)  { $verdict = 'large-shift' }
elseif ($deltaCount -gt 2)  { $verdict = 'minor-shift' }
$digestLines += "verdict=$verdict"

# Atomic digest write. Set-Content has been observed leaving the file
# truncated mid-line (e.g. stopping at "stamp=2026-05-0") if a reader
# grabs it between open and flush, OR if PS5.1 throws during write.
# Writing to a .tmp sibling and Move-Item -Force replaces the file in
# one syscall, so any reader either sees the full previous digest or
# the full new digest -- never a half file.
try {
    $digestTmp  = $digestPath + '.tmp'
    $digestBody = ($digestLines -join "`r`n") + "`r`n"
    Set-Content -Path $digestTmp -Value $digestBody -Encoding utf8 -NoNewline
    if (Test-Path $digestPath) {
        Remove-Item $digestPath -Force -ErrorAction SilentlyContinue
    }
    Move-Item -LiteralPath $digestTmp -Destination $digestPath -Force
} catch {
    PMLog "  digest write FAILED: $($_.Exception.Message)" Red
    # Last-ditch fallback so the file is at least non-empty for the
    # agent's freshness check.
    try { Set-Content -Path $digestPath -Value $digestLines -Encoding utf8 } catch { }
}

PMLog '== postmortem complete ==' Cyan
PMLog "  written to: $postmortemTxt"
if ($simExit -eq 0) {
    PMLog '  sim:       PASS' Green
} else {
    PMLog "  sim:       FAIL (exit=$simExit) -- regression caught" Red
}
exit 0
