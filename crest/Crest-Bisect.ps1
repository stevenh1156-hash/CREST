# =====================================================================
# Crest-Bisect.ps1
# =====================================================================
# Walk back through archived battle postmortems (last 3) and surface
# where a metric changed. Useful when something broke between runs and
# you want to know which build introduced the regression.
#
# Usage:
#   & C:\dev\bannerlord\crest\Crest-Bisect.ps1 -Metric 'overrides'
#   & C:\dev\bannerlord\crest\Crest-Bisect.ps1 -Metric 'wander-clamp'
#   & C:\dev\bannerlord\crest\Crest-Bisect.ps1 -Metric 'spot occupancy'
#   & C:\dev\bannerlord\crest\Crest-Bisect.ps1                    (all metrics)
#
# Output: side-by-side comparison of the metric across archived battles
# with a CHANGED marker if values differ between consecutive runs.
# =====================================================================

param(
    [string]$Metric = ''
)
$ErrorActionPreference = 'Continue'

$diagDir    = 'C:\dev\bannerlord\crest\.runner\diag'
$battlesDir = Join-Path $diagDir 'battles'

if (-not (Test-Path $battlesDir)) {
    Write-Host '[bisect] no battles archive yet (need at least 2 postmortems)' -ForegroundColor Yellow
    exit 0
}

$archives = Get-ChildItem $battlesDir -Directory -Filter 'battle-*' |
            Sort-Object Name -Descending |
            Select-Object -First 3

if (-not $archives -or $archives.Count -lt 2) {
    Write-Host "[bisect] need >=2 archives to bisect (have $($archives.Count))" -ForegroundColor Yellow
    exit 0
}

Write-Host "=== Crest-Bisect across $($archives.Count) battles ===" -ForegroundColor Cyan
Write-Host ''

# Default metrics to inspect if user didn't pick one.
$keysToCheck = @(
    'overrides:',
    'spot occupancy:',
    'spot orders:',
    'spot formations:',
    'pool tier txns:',
    'pool fallback:',
    'BEW exceptions:',
    'captain leaks:',
    'caught excs:',
    'scan:'
)
if ($Metric) { $keysToCheck = @($Metric) }

# Read each archive's postmortem.txt and pull the metric lines.
$rows = @()
foreach ($a in $archives) {
    $pm = Join-Path $a.FullName 'postmortem.txt'
    if (-not (Test-Path $pm)) { continue }
    $row = @{ Name = $a.Name; Lines = @{} }
    foreach ($k in $keysToCheck) {
        $hit = Select-String -Path $pm -SimpleMatch $k -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { $row.Lines[$k] = $hit.Line.Trim() }
    }
    $rows += $row
}

# Print side-by-side per metric.
foreach ($k in $keysToCheck) {
    $values = $rows | ForEach-Object { $_.Lines[$k] }
    if (-not ($values | Where-Object { $_ })) { continue }
    Write-Host ("---  $k  ---") -ForegroundColor Cyan
    $prev = $null
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $name = $rows[$i].Name
        $line = $rows[$i].Lines[$k]
        if (-not $line) { continue }
        $changed = ($prev -ne $null -and $line -ne $prev)
        $prefix  = if ($changed) { 'CHANGED' } else { '       ' }
        $color   = if ($changed) { 'Yellow' } else { 'Gray' }
        Write-Host ("  {0,-6} {1,-30}  {2}" -f $prefix, $name, $line) -ForegroundColor $color
        $prev = $line
    }
    Write-Host ''
}

Write-Host '=== bisect done ===' -ForegroundColor Cyan
exit 0
