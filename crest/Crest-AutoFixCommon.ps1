# =====================================================================
# Crest-AutoFixCommon.ps1 -- auto-resolve common iteration blockers.
# =====================================================================
# Detects + fixes common transient errors that would otherwise require
# AI intervention:
#
#   1. "DLL is locked"        -> Bannerlord running. Print clear instruction.
#   2. "stale obj/"           -> nuke obj/ folders, retry
#   3. "queue script stuck"   -> oldest queue file > 5 min old, move to
#                                .runner\queue-stuck\ for inspection
#   4. "record.on left over"  -> if no battle-start.txt within 30 min,
#                                clear record.on (probably abandoned cycle)
#   5. "duplicate readys"     -> if > 2 agent-ready-*.ps1 in queue, keep
#                                only newest (idempotent anyway)
#   6. "old recordings"       -> record-*.jsonl in module folder > 24h old
#                                that aren't archived, move to .runner\diag\orphan-recordings\
#
# Usage:
#   & C:\dev\bannerlord\crest\Crest-AutoFixCommon.ps1
#   & C:\dev\bannerlord\crest\Crest-AutoFixCommon.ps1 -DryRun
# =====================================================================

param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'

$crestRoot       = 'C:\dev\bannerlord\crest'
$crestModuleRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'
$queueDir        = Join-Path $crestRoot '.runner\queue'
$stuckDir        = Join-Path $crestRoot '.runner\queue-stuck'
$diagDir         = Join-Path $crestRoot '.runner\diag'

$applied = @()

Write-Host ''
Write-Host '== Crest-AutoFixCommon ==' -ForegroundColor Cyan
if ($DryRun) { Write-Host '  DRY RUN (no changes)' -ForegroundColor Yellow }
Write-Host ''

# 1. Bannerlord running -> can't deploy.
$bannerlord = Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue
if ($bannerlord) {
    Write-Host '  [1] Bannerlord IS running (PID ' + $bannerlord.Id + ') -- deploys will fail' -ForegroundColor Yellow
    Write-Host '      (no auto-fix; user must close the game before next deploy)' -ForegroundColor DarkGray
    $applied += 'bannerlord-running-warned'
} else {
    Write-Host '  [1] Bannerlord not running OK' -ForegroundColor DarkGray
}

# 2. Stale obj/ folders.
$staleObj = @()
foreach ($p in @(
    'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\obj',
    'C:\dev\bannerlord\Bannerlord.Harmony\sim\Crest.Harmony.Sim\obj'
)) {
    if (-not (Test-Path $p)) { continue }
    # Stale = mtime > 7 days (rebuilds bake fresh ones)
    $mt = (Get-Item $p).LastWriteTime
    if ((Get-Date) - $mt -gt [TimeSpan]::FromDays(7)) { $staleObj += $p }
}
if ($staleObj) {
    Write-Host "  [2] stale obj/ folders: $($staleObj.Count)" -ForegroundColor Yellow
    if (-not $DryRun) {
        foreach ($p in $staleObj) {
            try { Remove-Item $p -Recurse -Force -ErrorAction Stop; Write-Host "      cleaned $p" -ForegroundColor Green }
            catch { Write-Host "      failed $p $($_.Exception.Message)" -ForegroundColor Red }
        }
        $applied += 'cleaned-stale-obj'
    }
} else {
    Write-Host '  [2] obj/ folders OK' -ForegroundColor DarkGray
}

# 3. Stuck queue scripts.
if (Test-Path $queueDir) {
    $stuck = Get-ChildItem $queueDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
             Where-Object { (Get-Date) - $_.LastWriteTime -gt [TimeSpan]::FromMinutes(5) }
    if ($stuck) {
        Write-Host "  [3] stuck queue items: $($stuck.Count)" -ForegroundColor Yellow
        if (-not $DryRun) {
            New-Item -ItemType Directory -Path $stuckDir -Force | Out-Null
            foreach ($s in $stuck) {
                try { Move-Item $s.FullName $stuckDir -Force; Write-Host "      moved $($s.Name)" -ForegroundColor Green } catch { }
            }
            $applied += 'moved-stuck-queue'
        }
    } else {
        Write-Host '  [3] queue OK' -ForegroundColor DarkGray
    }
}

# 4. Abandoned record.on (no battle-start in 30 min).
$recordSentinel = Join-Path $crestModuleRoot 'record.on'
$battleStart    = Join-Path $diagDir 'battle-start.txt'
if (Test-Path $recordSentinel) {
    $stamp = if (Test-Path $battleStart) { (Get-Item $battleStart).LastWriteTime } else { [DateTime]::MinValue }
    if ((Get-Date) - $stamp -gt [TimeSpan]::FromMinutes(30)) {
        Write-Host '  [4] record.on present but battle-start.txt is stale -- abandoned' -ForegroundColor Yellow
        if (-not $DryRun) {
            try { Remove-Item $recordSentinel -Force; Write-Host '      cleared record.on' -ForegroundColor Green; $applied += 'cleared-abandoned-record' } catch { }
        }
    } else {
        Write-Host '  [4] record.on active (recent battle-start)' -ForegroundColor DarkGray
    }
} else {
    Write-Host '  [4] record.on not set' -ForegroundColor DarkGray
}

# 5. Duplicate auto-readys.
if (Test-Path $queueDir) {
    $readys = Get-ChildItem $queueDir -Filter 'agent-ready-*.ps1' -File -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime
    if ($readys.Count -gt 2) {
        Write-Host "  [5] $($readys.Count) auto-readys queued (only newest needed)" -ForegroundColor Yellow
        if (-not $DryRun) {
            $toRemove = $readys | Select-Object -First ($readys.Count - 1)
            foreach ($r in $toRemove) {
                try { Remove-Item $r.FullName -Force; Write-Host "      pruned $($r.Name)" -ForegroundColor Green } catch { }
            }
            $applied += 'pruned-duplicate-readys'
        }
    } else {
        Write-Host '  [5] queue ready count OK' -ForegroundColor DarkGray
    }
}

# 6. Old orphan recordings in module folder.
if (Test-Path $crestModuleRoot) {
    $cutoff = (Get-Date).AddHours(-24)
    $orphans = Get-ChildItem $crestModuleRoot -Filter 'record-*.jsonl' -File -ErrorAction SilentlyContinue |
               Where-Object { $_.LastWriteTime -lt $cutoff }
    if ($orphans) {
        Write-Host "  [6] orphan recordings: $($orphans.Count)" -ForegroundColor Yellow
        if (-not $DryRun) {
            $orphanDir = Join-Path $diagDir 'orphan-recordings'
            New-Item -ItemType Directory -Path $orphanDir -Force | Out-Null
            foreach ($o in $orphans) {
                try { Move-Item $o.FullName $orphanDir -Force; Write-Host "      archived $($o.Name)" -ForegroundColor Green } catch { }
            }
            $applied += 'archived-orphan-recordings'
        }
    } else {
        Write-Host '  [6] no orphan recordings' -ForegroundColor DarkGray
    }
}

Write-Host ''
if ($applied.Count -eq 0) {
    Write-Host '  nothing to fix' -ForegroundColor Green
} else {
    Write-Host "  fixes applied: $($applied -join ', ')" -ForegroundColor Green
}
Write-Host ''
exit 0
