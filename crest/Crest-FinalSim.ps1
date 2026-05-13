# =====================================================================
# Crest-FinalSim.ps1 -- the synthetic battle-suite that gates smoke tests.
# =====================================================================
# After every code change, before asking the user to play another in-game
# battle, run all N most-recent archived recordings through the current
# rule code via Crest.Harmony.Sim --replay. Compute a pass/fail score
# per recording: a "stable" verdict means the user can skip smoke testing
# this iteration; a "drifted" verdict means a real battle is warranted.
#
# Outputs:
#   .runner\diag\finalsim-<stamp>.txt -- per-battle drift report
#   .runner\diag\finalsim-verdict.txt -- one-word verdict for the digest
#                                         and HERALD dashboard.
#
# Verdicts (one-word, gates real-battle requirement):
#   stable          all replays show <2% drift; smoke test optional
#   minor-drift     2..10% drift; smoke test recommended
#   major-drift     >10% drift; smoke test required
#   no-recordings   not enough archived data to score; require smoke test
#
# Usage:
#   crest FinalSim              -- replays last 5 battles
#   crest FinalSim -N 10        -- replays last 10 battles
# =====================================================================

param(
    [int]$N = 5
)

$ErrorActionPreference = 'Continue'

$crestRoot   = 'C:\dev\bannerlord\crest'
$battlesDir  = Join-Path $crestRoot '.runner\diag\battles'
$diagDir     = Join-Path $crestRoot '.runner\diag'
$verdictPath = Join-Path $diagDir 'finalsim-verdict.txt'
$reportPath  = Join-Path $diagDir ("finalsim-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".txt")
$simProj     = 'C:\dev\bannerlord\Bannerlord.Harmony\sim\Crest.Harmony.Sim\Crest.Harmony.Sim.csproj'

Write-Host ''
Write-Host '== Crest FinalSim ==' -ForegroundColor Cyan

if (-not (Test-Path $battlesDir)) {
    Set-Content -Path $verdictPath -Value 'no-recordings' -Encoding utf8
    Write-Host '  no battles archive -> verdict=no-recordings' -ForegroundColor Yellow
    exit 1
}

# Pick last N recordings.
$recordings = Get-ChildItem $battlesDir -Directory -Filter 'battle-*' -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending |
              Select-Object -First $N |
              ForEach-Object { Join-Path $_.FullName 'record.jsonl' } |
              Where-Object { Test-Path $_ }

if (-not $recordings -or $recordings.Count -eq 0) {
    Set-Content -Path $verdictPath -Value 'no-recordings' -Encoding utf8
    Write-Host '  no record.jsonl files -> verdict=no-recordings' -ForegroundColor Yellow
    exit 1
}

Write-Host "  replaying $($recordings.Count) recordings"
Write-Host ''

$report = @()
$report += "FinalSim run at $(Get-Date -Format 'o')"
$report += "Recordings: $($recordings.Count)"
$report += ''

$totalTicks = 0
$totalDrift = 0
$perBattle  = @()

# Helper: parse the geometry recording (Y.73). Returns a hashtable of
# per-formation track stats (path length, max distance from start, average
# elevation, terrain-relative-height) plus terrain bounds.
function Get-GeometryStats {
    param([string]$Path)
    $stats = @{
        Frames        = 0
        Formations    = 0
        TotalPathLen  = 0.0
        MaxRange      = 0.0
        TerrainGridN  = 0
        TerrainMin    = $null
        TerrainMax    = $null
        TerrainSpread = 0.0
    }
    if (-not (Test-Path $Path)) { return $stats }
    $tracks = @{}      # tid_fid -> @{ first=Vec; prev=Vec; pathLen; maxR }
    foreach ($raw in Get-Content $Path -ErrorAction SilentlyContinue) {
        if (-not $raw) { continue }
        $obj = $null
        try { $obj = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue } catch { continue }
        if (-not $obj) { continue }
        switch ($obj.type) {
            'terrain' {
                $stats.TerrainGridN = [int]$obj.gridN
                if ($obj.h) {
                    $hMin = ($obj.h | Measure-Object -Minimum).Minimum
                    $hMax = ($obj.h | Measure-Object -Maximum).Maximum
                    $stats.TerrainMin = $hMin
                    $stats.TerrainMax = $hMax
                    $stats.TerrainSpread = [double]($hMax - $hMin)
                }
            }
            'f' {
                $key = "$($obj.tid)_$($obj.fid)"
                if (-not $tracks.ContainsKey($key)) {
                    $tracks[$key] = @{
                        FirstX = [double]$obj.x; FirstY = [double]$obj.y
                        PrevX  = [double]$obj.x; PrevY  = [double]$obj.y
                        PathLen = 0.0
                        MaxR    = 0.0
                    }
                }
                $tr = $tracks[$key]
                $dx = [double]$obj.x - $tr.PrevX
                $dy = [double]$obj.y - $tr.PrevY
                $tr.PathLen += [Math]::Sqrt($dx*$dx + $dy*$dy)
                $tr.PrevX = [double]$obj.x; $tr.PrevY = [double]$obj.y
                $rdx = [double]$obj.x - $tr.FirstX
                $rdy = [double]$obj.y - $tr.FirstY
                $r = [Math]::Sqrt($rdx*$rdx + $rdy*$rdy)
                if ($r -gt $tr.MaxR) { $tr.MaxR = $r }
                $stats.Frames++
            }
        }
    }
    foreach ($k in $tracks.Keys) {
        $tr = $tracks[$k]
        $stats.TotalPathLen += $tr.PathLen
        if ($tr.MaxR -gt $stats.MaxRange) { $stats.MaxRange = $tr.MaxR }
    }
    $stats.Formations = $tracks.Count
    return $stats
}

$totalGeomFrames    = 0
$totalGeomPath      = 0.0
$totalGeomFormations = 0
$totalGeomTerrainSpread = 0.0
$geomBattlesWith    = 0

foreach ($rec in $recordings) {
    $battle = Split-Path -Leaf (Split-Path -Parent $rec)
    $output = & dotnet run --project $simProj --no-restore -- --replay $rec 2>&1

    $ticks = 0; $drift = 0
    foreach ($line in $output) {
        if ($line -match 'total:\s+(\d+)\s+ticks') { $ticks = [int]$Matches[1] }
        if ($line -match 'drift:\s+(\d+)')        { $drift = [int]$Matches[1] }
    }
    $totalTicks += $ticks
    $totalDrift += $drift
    $pct = if ($ticks -gt 0) { 100.0 * $drift / $ticks } else { 0.0 }

    # Y.73: geometry analysis if the matching geometry archive exists.
    $geomPath = Join-Path (Split-Path -Parent $rec) 'record-geometry.jsonl'
    $geom     = Get-GeometryStats -Path $geomPath
    if ($geom.Frames -gt 0) {
        $geomBattlesWith++
        $totalGeomFrames     += $geom.Frames
        $totalGeomPath       += $geom.TotalPathLen
        $totalGeomFormations += $geom.Formations
        $totalGeomTerrainSpread += $geom.TerrainSpread
    }

    $perBattle += [pscustomobject]@{
        Battle    = $battle
        Ticks     = $ticks
        Drift     = $drift
        PctDrift  = $pct
        Frames    = $geom.Frames
        Forms     = $geom.Formations
        PathLen   = [int]$geom.TotalPathLen
        TSpread   = [int]$geom.TerrainSpread
    }

    $color = if ($drift -eq 0) { 'Green' } elseif ($pct -lt 2) { 'DarkGreen' } elseif ($pct -lt 10) { 'Yellow' } else { 'Red' }
    Write-Host ("  {0,-26} ticks={1,5}  drift={2,4}  ({3,5:F1}%)  geom={4} frames {5}f path={6}m relief={7}m" -f `
        $battle, $ticks, $drift, $pct, $geom.Frames, $geom.Formations, [int]$geom.TotalPathLen, [int]$geom.TerrainSpread) -ForegroundColor $color
    $report += ("  {0}  ticks={1}  drift={2}  ({3:F1}%)  frames={4}  forms={5}  path={6}m  relief={7}m" -f `
        $battle, $ticks, $drift, $pct, $geom.Frames, $geom.Formations, [int]$geom.TotalPathLen, [int]$geom.TerrainSpread)
}

$overallPct = if ($totalTicks -gt 0) { 100.0 * $totalDrift / $totalTicks } else { 0.0 }
$verdict = 'stable'
if     ($totalTicks -eq 0)    { $verdict = 'no-recordings' }
elseif ($overallPct -ge 10.0) { $verdict = 'major-drift' }
elseif ($overallPct -ge 2.0)  { $verdict = 'minor-drift' }

$report += ''
$report += "TOTAL  ticks=$totalTicks  drift=$totalDrift  ({0:F1}%)" -f $overallPct
if ($geomBattlesWith -gt 0) {
    $avgPath  = if ($geomBattlesWith) { [int]($totalGeomPath / $geomBattlesWith) } else { 0 }
    $avgRelief = if ($geomBattlesWith) { [int]($totalGeomTerrainSpread / $geomBattlesWith) } else { 0 }
    $report += ("GEOMETRY  battles_with_geom={0}/{1}  total_frames={2}  total_formations={3}  avg_path_per_battle={4}m  avg_relief={5}m" -f `
        $geomBattlesWith, $recordings.Count, $totalGeomFrames, $totalGeomFormations, $avgPath, $avgRelief)
} else {
    $report += "GEOMETRY  no record-geometry.jsonl in any archived battle (Y.73 build pending or recorder was off)"
}
$report += "VERDICT  $verdict"

Set-Content -Path $reportPath -Value $report -Encoding utf8
Set-Content -Path $verdictPath -Value $verdict -Encoding utf8

Write-Host ''
Write-Host ("  TOTAL  ticks={0}  drift={1}  ({2:F1}%)" -f $totalTicks, $totalDrift, $overallPct)
$vColor = switch ($verdict) {
    'stable'        { 'Green' }
    'minor-drift'   { 'Yellow' }
    'major-drift'   { 'Red' }
    default         { 'DarkGray' }
}
Write-Host "  VERDICT: $verdict" -ForegroundColor $vColor
Write-Host ''
Write-Host "  report: $reportPath"
Write-Host ''

if ($verdict -eq 'stable') { exit 0 }
elseif ($verdict -eq 'minor-drift') { exit 0 }
else { exit 1 }
