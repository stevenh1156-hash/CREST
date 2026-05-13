# =====================================================================
# Crest-DriftCheck.ps1 -- replay last N battles against current rules.
# =====================================================================
# After every code change to CrestFormationRules, run this to see how
# many decisions in past battles would now be different. Surfaces
# unintended rule-behavior drift before the user notices in-game.
#
# Reads the N most recent battle-*\record.jsonl files, runs each
# through `Crest.Harmony.Sim --replay`, prints a one-line verdict per
# battle plus a total drift count.
#
# Usage:
#   & C:\dev\bannerlord\crest\Crest-DriftCheck.ps1
#   & C:\dev\bannerlord\crest\Crest-DriftCheck.ps1 -N 5
# =====================================================================

param(
    [int]$N = 3
)

$ErrorActionPreference = 'Continue'

$battlesDir = 'C:\dev\bannerlord\crest\.runner\diag\battles'
$simProj    = 'C:\dev\bannerlord\Bannerlord.Harmony\sim\Crest.Harmony.Sim\Crest.Harmony.Sim.csproj'

if (-not (Test-Path $battlesDir)) {
    Write-Host "no battles archive at $battlesDir" -ForegroundColor Red
    exit 1
}

$recordings = Get-ChildItem $battlesDir -Directory -Filter 'battle-*' -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending |
              Select-Object -First $N |
              ForEach-Object { Join-Path $_.FullName 'record.jsonl' } |
              Where-Object { Test-Path $_ }

if (-not $recordings) {
    Write-Host 'no record.jsonl files in archived battles' -ForegroundColor Yellow
    exit 1
}

Write-Host ''
Write-Host "== drift check against $($recordings.Count) recordings ==" -ForegroundColor Cyan

$totalTicks = 0
$totalDrift = 0
foreach ($rec in $recordings) {
    $battle = Split-Path -Leaf (Split-Path -Parent $rec)
    $output = & dotnet run --project $simProj --no-restore -- --replay $rec 2>&1

    # Parse the sim's output: "  total: N ticks" and "  drift: M".
    $ticks = 0; $drift = 0
    foreach ($line in $output) {
        if ($line -match 'total:\s+(\d+)\s+ticks') { $ticks = [int]$Matches[1] }
        if ($line -match 'drift:\s+(\d+)')        { $drift = [int]$Matches[1] }
    }
    $totalTicks += $ticks
    $totalDrift += $drift

    $color = if ($drift -eq 0) { 'Green' } elseif ($drift -lt 5) { 'Yellow' } else { 'Red' }
    Write-Host ("  {0,-26} ticks={1,4}  drift={2}" -f $battle, $ticks, $drift) -ForegroundColor $color
}

Write-Host ''
$pct = if ($totalTicks -eq 0) { 0 } else { 100.0 * (1.0 - $totalDrift / $totalTicks) }
$verdict = if ($totalDrift -eq 0) { 'STABLE' } elseif ($totalDrift -lt 10) { 'MINOR-DRIFT' } else { 'SIGNIFICANT-DRIFT' }
$vColor  = if ($totalDrift -eq 0) { 'Green' } elseif ($totalDrift -lt 10) { 'Yellow' } else { 'Red' }
Write-Host ("  total: {0} ticks, {1} drift ({2:F1}% match) -- {3}" -f $totalTicks, $totalDrift, $pct, $verdict) -ForegroundColor $vColor
Write-Host ''
exit 0
