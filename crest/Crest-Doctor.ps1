# =====================================================================
# Crest-Doctor.ps1 -- diagnose + repair the 10 known classes of CREST
# breakage.
# =====================================================================
# Run when:
#   - the game crashes and you do not know why
#   - the build fails with cryptic CSxxxx errors
#   - the watcher seems dead (heartbeats stale, queue piling up)
#   - the agent says "the deployed DLL does not match" or "source tree
#     is corrupted"
#   - any time a battle ends with an unexpected verdict and you want a
#     full health snapshot before continuing
#
# What it checks (each gets PASS / WARN / FAIL):
#   01. Watcher liveness            -- is crest-dev.ps1 running + heart-
#                                      beating in the last 90 s?
#   02. Deploy hash sync            -- does Modules\CREST\bin\...\Crest.
#                                      Harmony.dll match the dev-tree
#                                      bin\Release\net472\ build?
#   03. .bak rollback availability  -- is Crest.Harmony.dll.bak present
#                                      and what sha is it? (for one-line
#                                      rollback if a bad deploy ships)
#   04. .crashed-* DLLs              -- list any saved-aside crashed DLLs
#                                      so we know what we have to compare
#                                      against
#   05. Source-tree integrity        -- scan all .cs files for the
#                                      "} expected" mid-method truncation
#                                      pattern (the bug that bit us
#                                      2026-05-09)
#   06. Missing-class references    -- grep SubModule.cs for TryApply
#                                      calls and verify each class is
#                                      defined in some .cs file
#   07. .fuse_hidden orphans         -- find filesystem ghost files in
#                                      the source tree and offer to clean
#   08. Queue depth / age            -- count items in .runner\queue\;
#                                      flag if oldest is more than 30 s
#                                      (likely watcher stuck)
#   09. Postmortem digest freshness  -- does the digest file mtime match
#                                      the newest postmortem result file?
#                                      (catches the atomic-write bug class)
#   10. dev-mode + record sentinels  -- list .runner\dev-mode.on and
#                                      Modules\CREST\record.on existence
#                                      so we know what auto-chains are
#                                      armed
#
# After all checks, prints a numbered list of suggested repairs. Pass
# -Apply to actually run the repair for a specific check (e.g.
# `-Apply 03` rolls back to .bak; `-Apply 07` deletes ghost files).
#
# Exit codes:
#   0  -- everything PASS or WARN
#   1  -- at least one FAIL detected
# =====================================================================

[CmdletBinding()]
param(
    # Optional: number of the check to apply a repair for (e.g. "03").
    # Without this, the script is read-only -- it just reports.
    [string]$Apply = '',

    # Skip the slow checks (file scans). Use for fast snapshot.
    [switch]$Fast
)

$ErrorActionPreference = 'Continue'

$crestRoot       = 'C:\dev\bannerlord\crest'
$harmonySrc      = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony'
$moduleRoot      = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'
$deployBin       = Join-Path $moduleRoot 'bin\Win64_Shipping_Client'
$deployedDll     = Join-Path $deployBin 'Crest.Harmony.dll'
$bakDll          = Join-Path $deployBin 'Crest.Harmony.dll.bak'
$devDll          = Join-Path $harmonySrc 'bin\Release\net472\Crest.Harmony.dll'
$eventsLog       = Join-Path $crestRoot '.runner\events.log'
$queueDir        = Join-Path $crestRoot '.runner\queue'
$resultsDir      = Join-Path $crestRoot '.runner\results'
$digestFile      = Join-Path $crestRoot '.runner\diag\postmortem-digest.txt'
$markerFile      = Join-Path $crestRoot '.runner\last-read-postmortem.txt'
$devModeSentinel = Join-Path $crestRoot '.runner\dev-mode.on'
$recordSentinel  = Join-Path $moduleRoot 'record.on'

# Color helpers.
function W($t,$c='Gray')   { Write-Host $t -ForegroundColor $c }
function Pass($t)          { W ('  PASS  ' + $t) Green }
function WarnL($t)         { W ('  WARN  ' + $t) Yellow }
function Fail($t)          { W ('  FAIL  ' + $t) Red }
function Hdr($n,$t)        { W ''; W ("=== $n. $t ===") Cyan }

$repairs = @{}   # check-id -> { description, action scriptblock }
$failCount = 0

# --------------------------------------------------------------------
# 01. Watcher liveness
# --------------------------------------------------------------------
Hdr '01' 'Watcher liveness'
$watcherAlive = $false
if (-not (Test-Path $eventsLog)) {
    Fail "events.log not found at $eventsLog"
    $failCount++
} else {
    try {
        $lastLine = Get-Content $eventsLog -Tail 1 -ErrorAction SilentlyContinue
        if ($lastLine -match '^\[(.+?)\]') {
            $ts = [DateTime]::Parse($Matches[1])
            $age = ((Get-Date) - $ts).TotalSeconds
            if ($age -lt 90) {
                $watcherAlive = $true
                Pass ("last heartbeat {0:N0}s ago" -f $age)
            } else {
                WarnL ("last heartbeat {0:N0}s ago (expected < 90s)" -f $age)
                $repairs['01'] = @{
                    desc   = 'Restart the watcher (close any old crest-dev.ps1 window first)'
                    action = { Start-Process powershell -ArgumentList '-NoProfile -File C:\dev\bannerlord\crest\tools\crest-dev.ps1' -Verb RunAs }
                }
            }
        } else {
            WarnL "events.log tail is unparseable"
        }
    } catch {
        WarnL "could not parse events.log: $($_.Exception.Message)"
    }
}

# --------------------------------------------------------------------
# 02. Deploy hash sync
# --------------------------------------------------------------------
Hdr '02' 'Deploy hash sync (dev-tree DLL vs deployed DLL)'
if (-not (Test-Path $deployedDll)) {
    Fail "deployed DLL missing: $deployedDll"; $failCount++
} elseif (-not (Test-Path $devDll)) {
    WarnL "dev-tree DLL not built yet ($devDll). Run a build."
} else {
    $devSha = (Get-FileHash $devDll).Hash.Substring(0,12)
    $depSha = (Get-FileHash $deployedDll).Hash.Substring(0,12)
    if ($devSha -eq $depSha) {
        Pass "match (sha $devSha)"
    } else {
        Fail "dev=$devSha  deployed=$depSha  -- deploy is stale"
        $failCount++
        $repairs['02'] = @{
            desc   = 'Re-run Deploy-CrestHarmony.ps1 to push dev-tree DLL into the module'
            action = { & 'C:\dev\bannerlord\crest\tools\Deploy-CrestHarmony.ps1' }
        }
    }
}

# --------------------------------------------------------------------
# 03. .bak rollback availability
# --------------------------------------------------------------------
Hdr '03' '.bak rollback availability'
if (Test-Path $bakDll) {
    $bakSha = (Get-FileHash $bakDll).Hash.Substring(0,12)
    $bakMt  = (Get-Item $bakDll).LastWriteTime
    Pass "$bakDll exists (sha $bakSha, mtime $bakMt)"
    $repairs['03'] = @{
        desc   = 'Roll back deployed DLL to the .bak (saves current as .crashed-<stamp>)'
        action = {
            $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
            $evict = $deployedDll + '.crashed-' + $stamp
            Move-Item $deployedDll $evict -Force
            Copy-Item $bakDll $deployedDll -Force
            Write-Host "rolled back: live now matches .bak; crashed saved as $evict" -ForegroundColor Green
        }
    }
} else {
    WarnL ".bak missing -- no one-line rollback available"
}

# --------------------------------------------------------------------
# 04. .crashed-* saved DLLs
# --------------------------------------------------------------------
Hdr '04' '.crashed-* saved DLLs (post-mortem evidence)'
$crashedDlls = Get-ChildItem $deployBin -Filter 'Crest.Harmony.dll.crashed-*' -File -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending
if ($crashedDlls) {
    foreach ($c in $crashedDlls) {
        $sha = (Get-FileHash $c.FullName).Hash.Substring(0,12)
        Pass ("{0}  sha={1}  ({2} bytes)" -f $c.Name, $sha, $c.Length)
    }
} else {
    Pass "no .crashed-* files (clean)"
}

# --------------------------------------------------------------------
# 05. Source-tree integrity (truncation scan)
# --------------------------------------------------------------------
Hdr '05' 'Source-tree integrity (mid-method truncation scan)'
if ($Fast) {
    WarnL 'skipped (-Fast)'
} else {
    $cs = Get-ChildItem $harmonySrc -Filter '*.cs' -File -ErrorAction SilentlyContinue |
          Where-Object { $_.FullName -notmatch '\\(obj|bin)\\' -and $_.Name -notlike '.fuse_hidden*' }
    $bad = @()
    foreach ($f in $cs) {
        try {
            $text = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
            if ($null -eq $text) { continue }
            # Truncation heuristic: file ends inside a method body (no
            # closing braces matching the open count).
            $opens  = ([regex]::Matches($text, '\{')).Count
            $closes = ([regex]::Matches($text, '\}')).Count
            if ($opens -ne $closes) {
                $bad += [pscustomobject]@{ Name=$f.Name; Opens=$opens; Closes=$closes }
            }
        } catch {}
    }
    if ($bad.Count -eq 0) {
        Pass "all $($cs.Count) source files have balanced braces"
    } else {
        foreach ($b in $bad) {
            Fail ("{0}: opens={1} closes={2}" -f $b.Name, $b.Opens, $b.Closes)
        }
        $failCount += $bad.Count
        $repairs['05'] = @{
            desc   = 'Inspect listed files. Common cause: editor crash mid-edit; check .runner\diag\recovered\ for backups.'
            action = { Start-Process explorer.exe (Join-Path $crestRoot '.runner\diag\recovered') }
        }
    }
}

# --------------------------------------------------------------------
# 06. Missing-class references in SubModule.cs
# --------------------------------------------------------------------
Hdr '06' 'Missing-class references in SubModule.cs TryApply calls'
$subMod = Join-Path $harmonySrc 'SubModule.cs'
if (-not (Test-Path $subMod)) {
    Fail "SubModule.cs not found at $subMod"; $failCount++
} else {
    $sub = Get-Content $subMod -Raw
    $tryApplyClasses = [regex]::Matches($sub, '\b(Crest[A-Za-z0-9]+)\.TryApply\(') |
                       ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    $missing = @()
    foreach ($cls in $tryApplyClasses) {
        $hit = Get-ChildItem $harmonySrc -Filter '*.cs' -File -ErrorAction SilentlyContinue |
               Where-Object { $_.FullName -notmatch '\\(obj|bin)\\' -and $_.Name -notlike '.fuse_hidden*' } |
               Where-Object { (Select-String -Path $_.FullName -Pattern "class\s+$cls" -SimpleMatch:$false -Quiet) } |
               Select-Object -First 1
        if (-not $hit) { $missing += $cls }
    }
    if ($missing.Count -eq 0) {
        Pass "all $($tryApplyClasses.Count) referenced classes have a definition"
    } else {
        foreach ($m in $missing) { Fail "$m referenced from SubModule.cs but no .cs file defines it" }
        $failCount += $missing.Count
        $repairs['06'] = @{
            desc   = 'Restore missing classes from .runner\diag\recovered\ilspy-out\Bannerlord.Harmony\, or comment out the TryApply calls in SubModule.cs.'
            action = { Start-Process explorer.exe (Join-Path $crestRoot '.runner\diag\recovered\ilspy-out\Bannerlord.Harmony') }
        }
    }
}

# --------------------------------------------------------------------
# 07. .fuse_hidden orphans
# --------------------------------------------------------------------
Hdr '07' 'filesystem ghost (.fuse_hidden) files in source tree'
$ghosts = Get-ChildItem $harmonySrc -Force -File -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -like '.fuse_hidden*' }
if ($ghosts) {
    foreach ($g in $ghosts) {
        WarnL ("{0}  ({1} bytes)" -f $g.Name, $g.Length)
    }
    $repairs['07'] = @{
        desc   = 'Delete the .fuse_hidden orphans (these are leftover content from files deleted while open; safe to remove if not needed for source recovery).'
        action = {
            foreach ($g in $ghosts) {
                try {
                    Remove-Item $g.FullName -Force -ErrorAction Stop
                    Write-Host "deleted: $($g.Name)" -ForegroundColor Green
                } catch {
                    Write-Host "could not delete $($g.Name): $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    }
} else {
    Pass "no .fuse_hidden ghosts (clean)"
}

# --------------------------------------------------------------------
# 08. Queue depth + age
# --------------------------------------------------------------------
Hdr '08' 'Queue depth + age (signs of a stuck watcher)'
if (-not (Test-Path $queueDir)) {
    Pass "queue dir does not exist (no work pending)"
} else {
    $items = Get-ChildItem $queueDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime
    if ($items.Count -eq 0) {
        Pass "queue empty"
    } else {
        $oldest = $items | Select-Object -First 1
        $age = ((Get-Date) - $oldest.LastWriteTime).TotalSeconds
        if ($age -gt 30) {
            Fail ("$($items.Count) item(s); oldest is {0:N0}s old ({1}) -- watcher likely stuck" -f $age, $oldest.Name)
            $failCount++
            $repairs['08'] = @{
                desc   = 'Watcher is not draining the queue. Restart it via repair 01.'
                action = { Start-Process powershell -ArgumentList '-NoProfile -File C:\dev\bannerlord\crest\tools\crest-dev.ps1' -Verb RunAs }
            }
        } else {
            WarnL ("$($items.Count) item(s); oldest {0:N0}s old (still within window)" -f $age)
        }
    }
}

# --------------------------------------------------------------------
# 09. Postmortem digest freshness
# --------------------------------------------------------------------
Hdr '09' 'Postmortem digest freshness (matches newest result?)'
if (-not (Test-Path $digestFile)) {
    WarnL "no digest file at $digestFile"
} else {
    $digestMt = (Get-Item $digestFile).LastWriteTime
    $newestPm = Get-ChildItem $resultsDir -Filter 'agent-postmortem-*.json' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($newestPm) {
        $delta = ($digestMt - $newestPm.LastWriteTime).TotalSeconds
        if ([Math]::Abs($delta) -lt 60) {
            Pass ("digest is fresh (mtime delta {0:N0}s vs newest postmortem)" -f $delta)
        } else {
            Fail ("digest is STALE (mtime $digestMt vs newest postmortem $($newestPm.LastWriteTime))")
            $failCount++
            $repairs['09'] = @{
                desc   = 'Re-run Crest-Postmortem to regenerate the digest from current state.'
                action = { & 'C:\dev\bannerlord\crest\Crest-Postmortem.ps1' }
            }
        }
    } else {
        WarnL "no postmortem result files exist yet"
    }
}

# --------------------------------------------------------------------
# 10. dev-mode + record sentinels
# --------------------------------------------------------------------
Hdr '10' 'Sentinels (dev-mode.on, record.on)'
if (Test-Path $devModeSentinel) {
    Pass ".runner\dev-mode.on present (auto-ready chain ARMED)"
} else {
    WarnL ".runner\dev-mode.on absent (auto-ready chain NOT armed)"
}
if (Test-Path $recordSentinel) {
    Pass "Modules\CREST\record.on present (recorder ARMED for next battle)"
} else {
    WarnL "Modules\CREST\record.on absent (recorder NOT armed -- next battle wont be replayable)"
}

# --------------------------------------------------------------------
# Summary + suggested repairs
# --------------------------------------------------------------------
W ''
W '=== Summary ===' Cyan
W ("  fails: $failCount") $(if ($failCount -gt 0) { 'Red' } else { 'Green' })
W ("  repairs available: $($repairs.Count)") DarkGray
if ($repairs.Count -gt 0) {
    W ''
    W 'Suggested repairs (pass -Apply <id> to run):' Cyan
    foreach ($id in ($repairs.Keys | Sort-Object)) {
        W ("  $id  $($repairs[$id].desc)") Yellow
    }
}

# --------------------------------------------------------------------
# Apply mode
# --------------------------------------------------------------------
if ($Apply) {
    W ''
    W "=== Applying repair $Apply ===" Cyan
    if (-not $repairs.ContainsKey($Apply)) {
        W "no repair available with id $Apply" Red
        exit 1
    }
    & $repairs[$Apply].action
    W "repair $Apply complete." Green
}

if ($failCount -gt 0) { exit 1 } else { exit 0 }
