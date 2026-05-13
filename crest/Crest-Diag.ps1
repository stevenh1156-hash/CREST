# =====================================================================
# Crest-Diag : ONE-STOP post-battle diagnostic VISION tool.
# =====================================================================
# Run after every battle. Produces everything Claude needs to "see" what
# happened: status, log snapshot, crash report, battle summary, top-down
# battle map PNG, screenshot collage JPG, and narrative timeline.
#
# Usage:
#   & C:\dev\bannerlord\crest\Crest-Diag.ps1
#
# Outputs land in C:\dev\bannerlord\crest\.runner\diag\.
# =====================================================================

$ErrorActionPreference = 'Continue'

$crestModuleDir = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'
$srcDll         = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll'
$dstDll         = "$crestModuleDir\bin\Win64_Shipping_Client\Crest.Harmony.dll"
$runtimeLog     = "$crestModuleDir\runtime.log"
$mainMenuLog    = "$crestModuleDir\main-menu-messages.log"
$crestJson      = "$crestModuleDir\crest.json"
$eventsLog      = 'C:\dev\bannerlord\crest\.runner\events.log'
$queueDir       = 'C:\dev\bannerlord\crest\.runner\queue'
$resultsDir     = 'C:\dev\bannerlord\crest\.runner\results'
$diagDir        = 'C:\dev\bannerlord\crest\.runner\diag'
$shotDir        = "$diagDir\screenshots"
New-Item -ItemType Directory -Path $diagDir -Force | Out-Null

# ---------------------------------------------------------------------
# 0. CLEAR -- wipe history + screen so each diag run starts fresh
# ---------------------------------------------------------------------
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
try { Clear-History } catch { }
try { if (Get-Module -ListAvailable -Name PSReadLine) { [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory() } } catch { }
try {
    $opts = Get-PSReadlineOption
    if ($opts -and $opts.HistorySavePath -and (Test-Path $opts.HistorySavePath)) { Remove-Item -Path $opts.HistorySavePath -Force }
} catch { }
Clear-Host
Write-Host '[Crest] history cleared.' -ForegroundColor DarkGray
$ErrorActionPreference = $prevEAP
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------
# 1. STATUS
# ---------------------------------------------------------------------
Write-Host ''
Write-Host '====== Crest-Diag ======' -ForegroundColor Cyan
Write-Host '== status =='            -ForegroundColor Cyan

$statusFile = Join-Path $diagDir 'status.txt'
if (Test-Path $statusFile) { Remove-Item $statusFile -Force }
function Sline($s) { $s | Tee-Object -FilePath $statusFile -Append | Out-Host }

Sline "=== CREST status @ $(Get-Date) ==="
Sline ''
Sline '--- Crest.Harmony.dll ---'
foreach ($p in @($srcDll, $dstDll)) {
    if (Test-Path $p) {
        $f = Get-Item $p
        $h = (Get-FileHash -Path $p -Algorithm SHA256).Hash.Substring(0,16)
        Sline ("{0,12:N0} bytes  sha={1}...  {2}  {3}" -f $f.Length, $h, $f.LastWriteTime, $p)
    } else { Sline "MISSING: $p" }
}
Sline ''
Sline '--- runtime.log ---'
if (Test-Path $runtimeLog) {
    $f = Get-Item $runtimeLog
    Sline ("{0,12:N0} bytes  modified {1}  ({2} mins ago)" -f $f.Length, $f.LastWriteTime, [int]((Get-Date) - $f.LastWriteTime).TotalMinutes)
} else { Sline "MISSING: $runtimeLog" }
Sline ''
Sline '--- events.log (last 5) ---'
if (Test-Path $eventsLog) { Get-Content $eventsLog -Tail 5 | ForEach-Object { Sline $_ } } else { Sline "MISSING: $eventsLog" }
Sline ''
Sline '--- queue ---'
if (Test-Path $queueDir) {
    $items = Get-ChildItem $queueDir -File -ErrorAction SilentlyContinue
    if ($items) { foreach ($i in $items) { Sline "  pending: $($i.Name) ($($i.LastWriteTime))" } }
    else { Sline '  (empty)' }
}
Sline ''
Sline '--- results (last 3) ---'
if (Test-Path $resultsDir) {
    Get-ChildItem $resultsDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 3 |
        ForEach-Object { Sline ("  {0,-50} {1}" -f $_.Name, $_.LastWriteTime) }
}
Sline ''

# ---------------------------------------------------------------------
# 2. SNAPSHOT
# ---------------------------------------------------------------------
Write-Host ''
Write-Host '== snapshot ==' -ForegroundColor Cyan
$pairs = @(
    @{ src = $runtimeLog;  dst = "$diagDir\runtime.log" }
    @{ src = $mainMenuLog; dst = "$diagDir\main-menu-messages.log" }
    @{ src = $crestJson;   dst = "$diagDir\crest.json" }
)
foreach ($p in $pairs) {
    if (Test-Path $p.src) {
        Copy-Item $p.src $p.dst -Force
        $f = Get-Item $p.src
        Write-Host ("[snap] {0,-30} {1,12:N0} bytes  modified {2}" -f $f.Name, $f.Length, $f.LastWriteTime)
    } else { Write-Host "[snap] $($p.src) MISSING" -ForegroundColor DarkYellow }
}

# ---------------------------------------------------------------------
# 3. CRASH
# ---------------------------------------------------------------------
Write-Host ''
Write-Host '== crash =='  -ForegroundColor Cyan
$crashCandidates = @(
    "$env:USERPROFILE\Documents\Mount and Blade II Bannerlord\crashes"
    "$env:LOCALAPPDATA\Mount and Blade II Bannerlord\crashes"
    "$env:USERPROFILE\AppData\LocalLow\Mount and Blade II Bannerlord\crashes"
    "$env:USERPROFILE\Documents\Mount and Blade II Bannerlord"
    "$env:LOCALAPPDATA\Mount and Blade II Bannerlord"
    "$env:USERPROFILE\AppData\LocalLow\Mount and Blade II Bannerlord"
)
$crashFound = @()
foreach ($d in $crashCandidates) {
    if (Test-Path $d) { $crashFound += Get-ChildItem -Path $d -Filter 'crashreport*.html' -File -Recurse -ErrorAction SilentlyContinue }
}
if (-not $crashFound -or $crashFound.Count -eq 0) {
    Write-Host '[crash] no crashreport*.html found in any standard location' -ForegroundColor Yellow
} else {
    $latest = $crashFound | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $crashDst = Join-Path $diagDir 'latest-crash.html'
    Copy-Item $latest.FullName $crashDst -Force
    Write-Host "[crash] copied $($latest.Name) ($($latest.Length) bytes, $($latest.LastWriteTime))" -ForegroundColor Green
    try { Copy-Item $latest.FullName (Join-Path $crestModuleDir $latest.Name) -Force } catch { }
    try {
        $raw = Get-Content $latest.FullName -Raw
        $stripped = ($raw -replace '<[^>]+>',' ') -replace '\s+',' '
        $idx = $stripped.IndexOf('Exception Information')
        if ($idx -ge 0) {
            $excerpt = $stripped.Substring($idx, [Math]::Min(2000, $stripped.Length - $idx))
            Set-Content -Path "$diagDir\latest-crash-exception.txt" -Value $excerpt -Encoding utf8
            Write-Host '------- exception (first 700 chars) -------' -ForegroundColor Yellow
            Write-Host $excerpt.Substring(0, [Math]::Min(700, $excerpt.Length))
        }
    } catch { Write-Host "[crash] excerpt extraction failed: $_" -ForegroundColor DarkYellow }
}

# ---------------------------------------------------------------------
# 4. BATTLE summary text
# ---------------------------------------------------------------------
Write-Host ''
Write-Host '== battle summary ==' -ForegroundColor Cyan
$logSnap   = "$diagDir\runtime.log"
$summary   = "$diagDir\battle-summary.txt"
if (Test-Path $summary) { Remove-Item $summary -Force }
function Bline($s) { $s | Add-Content -Path $summary -Encoding utf8; $s | Out-Host }

$lines = @()
$lastStart = -1
if (Test-Path $logSnap) {
    $lines = Get-Content $logSnap
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -match 'Y\.12d AfterStart') { $lastStart = $i; break }
    }
}

if (-not (Test-Path $logSnap)) {
    Bline "[battle] no snapshot to read"
} elseif ($lastStart -lt 0) {
    Bline "[battle] no 'Y.12d AfterStart' line found -- pasting last 80 lines"
    $lines | Select-Object -Last 80 | ForEach-Object { Bline $_ }
} else {
    $slice = $lines[$lastStart..($lines.Count - 1)]
    Bline "=== Battle starting at line $lastStart of snapshot, $($slice.Count) lines ==="
    Bline ''
    $slice | Where-Object { $_ -match 'AfterStart|Y\.30:|Y\.34:|Y\.35:|Y\.42c qs-discovery|patched.*(UpdateBrushesWidget|RegisterBlow|SetDefault)' } |
        ForEach-Object { Bline $_ }
    Bline ''
    Bline '--- joiner registrations + routing ---'
    $slice | Where-Object { $_ -match 'registered .* on |auto-balance:|relation-override:|cap reached on .*; .* added to waiting list' } |
        ForEach-Object { Bline $_ }
    Bline ''
    Bline '--- pool tier / variant transitions ---'
    $slice | Where-Object { $_ -match 'Y\.30B:|Y\.34: pool anchors set' } | ForEach-Object { Bline $_ }
    Bline ''
    Bline '--- party eliminations ---'
    $slice | Where-Object { $_ -match 'party eliminated' } | ForEach-Object { Bline $_ }
    Bline ''
    Bline '--- engine-quirk patches firing ---'
    $slice | Where-Object { $_ -match 'BrushRace|qs-discovery' } | ForEach-Object { Bline $_ }
    Bline ''
    Bline '--- Y.59 battle plan (terrain-picked spawn spots) ---'
    $slice | Where-Object { $_ -match 'Y\.59 (terrain-scan|battle-plan)|Y\.60a spot-formation' } | ForEach-Object { Bline $_ }
    Bline ''
    Bline '--- Y.60c spot diagnostics (per-spot fill + state) ---'
    $slice | Where-Object { $_ -match 'Y\.60c \[' } | Select-Object -Last 30 | ForEach-Object { Bline $_ }
    Bline ''
    Bline '--- Y.60d spot tier/variant orders ---'
    $slice | Where-Object { $_ -match 'Y\.60d spot-orders' } | Select-Object -Last 20 | ForEach-Object { Bline $_ }
    Bline ''
    Bline '--- Y.65/66/67 (structures, LOS, ambush discovery) ---'
    $slice | Where-Object { $_ -match 'Y\.65 |Y\.66 |Y\.67 |entity-discovery|los-discovery|structure-scan|Y\.65 walk|Y\.65 probe|Y\.65 RootEntityCount' } | ForEach-Object { Bline $_ }
    Bline ''
    Bline '--- Y.54 formation overrides ---'
    $slice | Where-Object { $_ -match 'Y\.54 override|Y\.56 clear' } | ForEach-Object { Bline $_ }
    Bline ''
    Bline '--- BEW exception popups (Y.55 mirror) ---'
    # BEW lines are tagged "[BEW]" by ExceptionReporter.Show. Surface them
    # in their own block so a popup that fired in-game is unmissable in
    # the diag, even if the user dismissed the window without copying.
    $slice | Where-Object { $_ -match '\[BEW\]' } | ForEach-Object { Bline $_ }
    Bline ''
    Bline '--- caught exceptions / errors ---'
    $slice | Where-Object { $_ -match 'CrestDiag.*ex|exception|ERROR|MBException' -and $_ -notmatch 'Y\.42 ' -and $_ -notmatch '\[BEW\]' } |
        ForEach-Object { Bline $_ }
    Bline ''
    Bline '--- final Y.42 cycle ---'
    $lastY42 = $slice | Where-Object { $_ -match 'Y\.42 ' } | Select-Object -Last 30
    $lastY42 | ForEach-Object { Bline $_ }
    Bline ''
    $endLines = $slice | Where-Object { $_ -match 'OnEndMission|detached \d+ joiner parties' }
    if ($endLines) { Bline '--- mission end ---'; $endLines | ForEach-Object { Bline $_ } }
}

# ---------------------------------------------------------------------
# 5. BATTLE MAP -- top-down PNG of final pool positions
# ---------------------------------------------------------------------
Write-Host ''
Write-Host '== battle map ==' -ForegroundColor Cyan
try {
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

    if ($lastStart -ge 0) {
        $slice = $lines[$lastStart..($lines.Count - 1)]

        # Parse anchors from Y.34 lines + final Y.42 formations
        $anchors = @{}
        foreach ($l in $slice) {
            if ($l -match 'Y\.34: pool anchors set inf=\(([-\d.]+),([-\d.]+)\) arch=\(([-\d.]+),([-\d.]+)\) cav=\(([-\d.]+),([-\d.]+)\)') {
                $anchors['inf'] = @([double]$Matches[1], [double]$Matches[2])
                $anchors['arch'] = @([double]$Matches[3], [double]$Matches[4])
                $anchors['cav']  = @([double]$Matches[5], [double]$Matches[6])
            }
        }

        # Find timestamp of LAST Y.42 cycle
        $lastTs = $null
        for ($i = $slice.Count - 1; $i -ge 0; $i--) {
            if ($slice[$i] -match 'Y\.42 \[\w+\.\d+\] (inf|arch|cav):') {
                if ($slice[$i] -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') { $lastTs = $Matches[1]; break }
            }
        }

        $formations = @()
        if ($lastTs) {
            # Escape the leading '[' since PowerShell -like treats it as a
            # character-class start. Use -match (regex) on a substring instead.
            $tsPattern = [regex]::Escape($lastTs)
            $cycleLines = $slice | Where-Object { $_ -match "^\[$tsPattern" -and $_ -match 'Y\.42 \[' }
            foreach ($l in $cycleLines) {
                if ($l -match 'Y\.42 \[(\w+)\.(\d+)\] (\w+): units=(\d+) pos=\(([-\d.]+),([-\d.]+)\) anchorD=([-\d.]+) enemyD=([-\d.]+) .*beh=(\S+)') {
                    $formations += [PSCustomObject]@{
                        Side   = $Matches[1]
                        Pool   = [int]$Matches[2]
                        Class  = $Matches[3]
                        Units  = [int]$Matches[4]
                        X      = [double]$Matches[5]
                        Y      = [double]$Matches[6]
                        AnchorDist = [double]$Matches[7]
                        EnemyDist  = [double]$Matches[8]
                        Beh    = $Matches[9]
                    }
                }
            }
        }

        if ($formations.Count -eq 0) {
            Write-Host '[map] no Y.42 formations parsed -- skipping map render' -ForegroundColor DarkYellow
        } else {
            # Compute bounds
            $allX = @($formations | ForEach-Object { $_.X })
            $allY = @($formations | ForEach-Object { $_.Y })
            $minX = ($allX | Measure-Object -Minimum).Minimum
            $maxX = ($allX | Measure-Object -Maximum).Maximum
            $minY = ($allY | Measure-Object -Minimum).Minimum
            $maxY = ($allY | Measure-Object -Maximum).Maximum
            # Pad bounds; if all positions are 0 fall back to a visible canvas
            if ($maxX - $minX -lt 1.0) { $minX -= 50; $maxX += 50 }
            if ($maxY - $minY -lt 1.0) { $minY -= 50; $maxY += 50 }
            $padPct = 0.10
            $w = $maxX - $minX; $h = $maxY - $minY
            $minX -= $w * $padPct; $maxX += $w * $padPct
            $minY -= $h * $padPct; $maxY += $h * $padPct

            $imgW = 900; $imgH = 900
            $bmp = New-Object System.Drawing.Bitmap $imgW, $imgH
            $g   = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $g.Clear([System.Drawing.Color]::FromArgb(20,24,30))

                # Helper: world(x,y) -> screen(px,py). NOTE: invert Y so north
                # is up in the rendered image (Bannerlord world Y grows northward).
                function W2S([double]$x, [double]$y) {
                    $px = [int](($x - $minX) / ($maxX - $minX) * $imgW)
                    $py = [int]($imgH - ($y - $minY) / ($maxY - $minY) * $imgH)
                    return @($px, $py)
                }

                # Grid
                $gridPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(40,46,55)), 1
                for ($i = 0; $i -lt 10; $i++) {
                    $g.DrawLine($gridPen, [int]($i * $imgW / 10), 0, [int]($i * $imgW / 10), $imgH)
                    $g.DrawLine($gridPen, 0, [int]($i * $imgH / 10), $imgW, [int]($i * $imgH / 10))
                }
                $gridPen.Dispose()

                # Title + axis labels
                $titleFont = New-Object System.Drawing.Font 'Consolas', 12, ([System.Drawing.FontStyle]::Bold)
                $smallFont = New-Object System.Drawing.Font 'Consolas', 9
                $whiteBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
                $grayBrush  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(160,170,180))

                $g.DrawString("Battle Map -- final Y.42 cycle  $lastTs", $titleFont, $whiteBrush, 8, 6)
                $g.DrawString(("X: {0:N0} .. {1:N0}" -f $minX, $maxX), $smallFont, $grayBrush, 8, $imgH - 32)
                $g.DrawString(("Y: {0:N0} .. {1:N0}" -f $minY, $maxY), $smallFont, $grayBrush, 8, $imgH - 18)

                # Side palette
                $colors = @{
                    'ally.0'  = [System.Drawing.Color]::FromArgb(80,160,255)
                    'ally.1'  = [System.Drawing.Color]::FromArgb(120,200,255)
                    'enemy.0' = [System.Drawing.Color]::FromArgb(255,90,90)
                    'enemy.1' = [System.Drawing.Color]::FromArgb(255,140,140)
                }
                $classFill = @{ 'inf' = 1.0; 'arch' = 0.7; 'cav' = 0.4 }   # used for alpha differentiation

                foreach ($f in $formations) {
                    $key = "$($f.Side).$($f.Pool)"
                    $base = if ($colors.ContainsKey($key)) { $colors[$key] } else { [System.Drawing.Color]::Yellow }
                    $alpha = if ($classFill.ContainsKey($f.Class)) { [int](255 * $classFill[$f.Class]) } else { 200 }
                    $col = [System.Drawing.Color]::FromArgb($alpha, $base.R, $base.G, $base.B)
                    $brush = New-Object System.Drawing.SolidBrush $col
                    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 1

                    # Radius scaled by sqrt(units), clamped 6..40
                    $radius = [Math]::Max(6, [Math]::Min(40, [int]([Math]::Sqrt([double]$f.Units) * 2.0)))
                    $sp = W2S $f.X $f.Y
                    $g.FillEllipse($brush, $sp[0] - $radius, $sp[1] - $radius, $radius * 2, $radius * 2)
                    $g.DrawEllipse($pen, $sp[0] - $radius, $sp[1] - $radius, $radius * 2, $radius * 2)

                    $label = "$($f.Side).$($f.Pool) $($f.Class) $($f.Units)u $($f.Beh)"
                    $g.DrawString($label, $smallFont, $whiteBrush, $sp[0] + $radius + 2, $sp[1] - 8)
                    $brush.Dispose(); $pen.Dispose()
                }

                # Legend
                $legY = 28
                $legX = $imgW - 220
                $legFont = $smallFont
                $g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(180,0,0,0))), $legX - 6, $legY - 6, 220, 78)
                $g.DrawString('LEGEND', $legFont, $whiteBrush, $legX, $legY); $legY += 14
                foreach ($k in @('ally.0','ally.1','enemy.0','enemy.1')) {
                    if ($colors.ContainsKey($k)) {
                        $b = New-Object System.Drawing.SolidBrush $colors[$k]
                        $g.FillRectangle($b, $legX, $legY + 2, 12, 12)
                        $g.DrawString($k, $legFont, $whiteBrush, $legX + 18, $legY)
                        $legY += 14
                        $b.Dispose()
                    }
                }

                $titleFont.Dispose(); $smallFont.Dispose(); $whiteBrush.Dispose(); $grayBrush.Dispose()
            } finally { $g.Dispose() }

            $mapPath = Join-Path $diagDir 'battle-map.png'
            $bmp.Save($mapPath, [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
            Write-Host "[map] rendered $($formations.Count) formations  ->  $mapPath" -ForegroundColor Green
        }
    } else {
        Write-Host '[map] no battle slice -- skipping' -ForegroundColor DarkYellow
    }
} catch { Write-Host "[map] render failed: $_" -ForegroundColor Red }

# ---------------------------------------------------------------------
# 5b. BATTLE TRAILS -- one PNG with each formation's full path traced
#     across all Y.42 cycles in the slice. Color same as map: blue=ally
#     red=enemy, line thickness = cycle count.
# ---------------------------------------------------------------------
Write-Host ''
Write-Host '== battle trails ==' -ForegroundColor Cyan
try {
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    if ($lastStart -ge 0) {
        $slice = $lines[$lastStart..($lines.Count - 1)]
        # Parse every Y.42 cycle: build hashtable side.pool.class -> ordered list of (x,y,units)
        $tracks = @{}
        foreach ($l in $slice) {
            if ($l -match 'Y\.42 \[(\w+)\.(\d+)\] (\w+): units=(\d+) pos=\(([-\d.]+),([-\d.]+)\)') {
                $key = "$($Matches[1]).$($Matches[2]).$($Matches[3])"
                if (-not $tracks.ContainsKey($key)) { $tracks[$key] = @() }
                $tracks[$key] += [PSCustomObject]@{
                    X = [double]$Matches[5]; Y = [double]$Matches[6]; U = [int]$Matches[4]
                }
            }
        }
        if ($tracks.Count -eq 0) {
            Write-Host '[trails] no Y.42 cycles parsed' -ForegroundColor DarkYellow
        } else {
            $allPts = @()
            foreach ($k in $tracks.Keys) { $allPts += $tracks[$k] }
            $minX = ($allPts | ForEach-Object { $_.X } | Measure-Object -Minimum).Minimum
            $maxX = ($allPts | ForEach-Object { $_.X } | Measure-Object -Maximum).Maximum
            $minY = ($allPts | ForEach-Object { $_.Y } | Measure-Object -Minimum).Minimum
            $maxY = ($allPts | ForEach-Object { $_.Y } | Measure-Object -Maximum).Maximum
            if ($maxX - $minX -lt 1.0) { $minX -= 50; $maxX += 50 }
            if ($maxY - $minY -lt 1.0) { $minY -= 50; $maxY += 50 }
            $padPct = 0.10
            $w = $maxX - $minX; $h = $maxY - $minY
            $minX -= $w * $padPct; $maxX += $w * $padPct
            $minY -= $h * $padPct; $maxY += $h * $padPct

            $imgW = 900; $imgH = 900
            $bmp = New-Object System.Drawing.Bitmap $imgW, $imgH
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $g.Clear([System.Drawing.Color]::FromArgb(20,24,30))
                # grid
                $gp = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(40,46,55)),1
                for ($i=0; $i -lt 10; $i++) {
                    $g.DrawLine($gp, [int]($i*$imgW/10), 0, [int]($i*$imgW/10), $imgH)
                    $g.DrawLine($gp, 0, [int]($i*$imgH/10), $imgW, [int]($i*$imgH/10))
                }
                $gp.Dispose()
                $titleFont = New-Object System.Drawing.Font 'Consolas',12,([System.Drawing.FontStyle]::Bold)
                $smallFont = New-Object System.Drawing.Font 'Consolas',9
                $whiteBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
                $g.DrawString("Movement trails -- $($tracks.Count) tracks across all Y.42 cycles", $titleFont, $whiteBrush, 8, 6)

                $colors = @{
                    'ally.0'=[System.Drawing.Color]::FromArgb(80,160,255);  'ally.1'=[System.Drawing.Color]::FromArgb(120,200,255)
                    'enemy.0'=[System.Drawing.Color]::FromArgb(255,90,90); 'enemy.1'=[System.Drawing.Color]::FromArgb(255,140,140)
                }
                foreach ($k in $tracks.Keys) {
                    $parts = $k -split '\.'
                    $sk = "$($parts[0]).$($parts[1])"
                    $cls = $parts[2]
                    $base = if ($colors.ContainsKey($sk)) { $colors[$sk] } else { [System.Drawing.Color]::Yellow }
                    # alpha stronger for inf, lighter for arch/cav so overlapping tracks are readable
                    $alpha = if ($cls -eq 'inf') { 220 } elseif ($cls -eq 'arch') { 160 } else { 120 }
                    $col = [System.Drawing.Color]::FromArgb($alpha,$base.R,$base.G,$base.B)
                    $pen = New-Object System.Drawing.Pen $col, 2
                    $brush = New-Object System.Drawing.SolidBrush $col
                    $pts = $tracks[$k]
                    if ($pts.Count -lt 1) { continue }
                    # draw as polyline + dot at each cycle
                    $sxs = @(); $sys = @()
                    foreach ($p in $pts) {
                        $sx = [int](($p.X - $minX) / ($maxX - $minX) * $imgW)
                        $sy = [int]($imgH - ($p.Y - $minY) / ($maxY - $minY) * $imgH)
                        $sxs += $sx; $sys += $sy
                    }
                    for ($i = 0; $i -lt ($sxs.Count - 1); $i++) {
                        $g.DrawLine($pen, $sxs[$i], $sys[$i], $sxs[$i+1], $sys[$i+1])
                    }
                    foreach ($i in 0..($sxs.Count-1)) {
                        $r = if ($i -eq ($sxs.Count - 1)) { 6 } else { 2 }
                        $g.FillEllipse($brush, $sxs[$i]-$r, $sys[$i]-$r, $r*2, $r*2)
                    }
                    # label end-point
                    if ($sxs.Count -gt 0) {
                        $lx = $sxs[$sxs.Count - 1] + 8; $ly = $sys[$sys.Count - 1] - 6
                        $g.DrawString("$k ($($pts[$pts.Count-1].U)u)", $smallFont, $whiteBrush, $lx, $ly)
                    }
                    $pen.Dispose(); $brush.Dispose()
                }
                $titleFont.Dispose(); $smallFont.Dispose(); $whiteBrush.Dispose()
            } finally { $g.Dispose() }
            $tp = Join-Path $diagDir 'battle-trails.png'
            $bmp.Save($tp, [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
            Write-Host "[trails] $($tracks.Count) tracks, total cycles=$(($tracks.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum)  ->  $tp" -ForegroundColor Green
        }
    } else {
        Write-Host '[trails] no battle slice -- skipping' -ForegroundColor DarkYellow
    }
} catch { Write-Host "[trails] render failed: $_" -ForegroundColor Red }

# ---------------------------------------------------------------------
# 6. SCREENSHOT COLLAGE -- 3x3 grid of evenly-sampled frames
# ---------------------------------------------------------------------
Write-Host ''
Write-Host '== screenshot collage ==' -ForegroundColor Cyan
try {
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    if (-not (Test-Path $shotDir)) {
        Write-Host '[collage] (no screenshots dir; run Screenshot-Loop.ps1 in a separate window for visual frames)' -ForegroundColor DarkYellow
    } else {
        # Filter to screenshots taken DURING this battle if we have a start timestamp.
        $startStamp = $null
        if ($lastStart -ge 0 -and $lines[$lastStart] -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
            try { $startStamp = [DateTime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', $null) } catch { }
        }
        $shots = Get-ChildItem $shotDir -Filter 'shot-*.jpg' -File -ErrorAction SilentlyContinue
        if ($startStamp) { $shots = $shots | Where-Object { $_.LastWriteTime -ge $startStamp.AddSeconds(-5) } }
        $shots = $shots | Sort-Object LastWriteTime

        if ($shots.Count -eq 0) {
            Write-Host '[collage] no screenshots in battle window' -ForegroundColor DarkYellow
        } else {
            # Evenly sample 9 frames
            $picks = @()
            if ($shots.Count -le 9) { $picks = $shots }
            else {
                for ($i = 0; $i -lt 9; $i++) {
                    $idx = [int]([Math]::Round($i * ($shots.Count - 1) / 8.0))
                    $picks += $shots[$idx]
                }
            }

            $cellSize = 320; $cols = 3; $rows = [Math]::Ceiling($picks.Count / [double]$cols)
            $imgW = $cellSize * $cols; $imgH = $cellSize * $rows
            $cbmp = New-Object System.Drawing.Bitmap $imgW, $imgH
            $cg = [System.Drawing.Graphics]::FromImage($cbmp)
            try {
                $cg.Clear([System.Drawing.Color]::Black)
                $captionFont = New-Object System.Drawing.Font 'Consolas', 10, ([System.Drawing.FontStyle]::Bold)
                $captionBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
                $captionShadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(180,0,0,0))

                for ($i = 0; $i -lt $picks.Count; $i++) {
                    $r = [Math]::Floor($i / $cols); $c = $i % $cols
                    $x = $c * $cellSize; $y = $r * $cellSize
                    try {
                        $img = [System.Drawing.Image]::FromFile($picks[$i].FullName)
                        $cg.DrawImage($img, $x, $y, $cellSize, $cellSize)
                        $img.Dispose()
                    } catch { }
                    $cap = "{0}: {1:HH:mm:ss}" -f ($i + 1), $picks[$i].LastWriteTime
                    $cg.FillRectangle($captionShadow, $x + 4, $y + 4, 110, 16)
                    $cg.DrawString($cap, $captionFont, $captionBrush, $x + 6, $y + 4)
                }
                $captionFont.Dispose(); $captionBrush.Dispose(); $captionShadow.Dispose()
            } finally { $cg.Dispose() }

            $collagePath = Join-Path $diagDir 'battle-collage.jpg'
            $jpegEncoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
            $epars = New-Object System.Drawing.Imaging.EncoderParameters 1
            $epars.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [int64]75)
            $cbmp.Save($collagePath, $jpegEncoder, $epars)
            $cbmp.Dispose()
            Write-Host "[collage] sampled $($picks.Count) frames from $($shots.Count) total  ->  $collagePath" -ForegroundColor Green
        }
    }
} catch { Write-Host "[collage] failed: $_" -ForegroundColor Red }

# ---------------------------------------------------------------------
# 7. NARRATIVE -- markdown timeline of key events
# ---------------------------------------------------------------------
Write-Host ''
Write-Host '== narrative ==' -ForegroundColor Cyan
try {
    if ($lastStart -ge 0) {
        $slice = $lines[$lastStart..($lines.Count - 1)]
        $narrative = "$diagDir\battle-narrative.md"
        if (Test-Path $narrative) { Remove-Item $narrative -Force }
        function Nline($s) { $s | Add-Content -Path $narrative -Encoding utf8 }

        Nline "# Battle narrative"
        Nline ""
        $st = if ($lines[$lastStart] -match '^\[([\d :-]+)') { $Matches[1] } else { '?' }
        Nline "Started: **$st**"
        Nline ""
        Nline "## Timeline"
        Nline ""
        foreach ($l in $slice) {
            $tsm = ''; if ($l -match '^\[([\d :-]+)') { $tsm = $Matches[1] }
            $line = $null
            switch -Regex ($l) {
                'AfterStart'                              { $line = "- **$tsm** mission started -- $($l -replace '.*AfterStart: ','')"; break }
                'ensured \d+ ally pools'                  { $line = "- **$tsm** $($l -replace '.*Y\.30: ',':moneybag: ')"; break }
                'ensured \d+ enemy pools'                 { $line = "- **$tsm** $($l -replace '.*Y\.35: ',':crossed_swords: ')"; break }
                'queued .* on '                           { $line = "- **$tsm** :inbox_tray: $($l -replace '.*\] ','')"; break }
                'registered .* on '                       { $line = "- **$tsm** :handshake: $($l -replace '.*\] ','')"; break }
                'auto-balance:'                           { $line = "- **$tsm** :balance_scale: $($l -replace '.*\] ','')"; break }
                'relation-override:'                      { $line = "- **$tsm** :star: $($l -replace '.*\] ','')"; break }
                'cap reached on'                          { $line = "- **$tsm** :hourglass: $($l -replace '.*\] ','')"; break }
                'pool tier=.*variant='                    { $line = "- **$tsm** :shield: $($l -replace '.*\] ','')"; break }
                'pool anchors set'                        { $line = "- **$tsm** :round_pushpin: $($l -replace '.*\] ','')"; break }
                'party eliminated'                        { $line = "- **$tsm** :skull: $($l -replace '.*\] ','')"; break }
                'BrushRace.*swallowed'                    { $line = "- **$tsm** :wrench: $($l -replace '.*\] ','')"; break }
                'Y\.54 override'                          { $line = "- **$tsm** :traffic_light: $($l -replace '.*\] ','')"; break }
                '\[BEW\]'                                 { $line = "- **$tsm** :rotating_light: BEW: $($l -replace '.*\[BEW\] ','')"; break }
                'OnEndMission'                            { $line = "- **$tsm** :checkered_flag: mission ended"; break }
                'exception|MBException'                   {
                    if ($l -notmatch 'Y\.42 ' -and $l -notmatch '\[BEW\]') { $line = "- **$tsm** :warning: $($l -replace '.*\] ','')" }
                    break
                }
            }
            if ($line) { Nline $line }
        }
        Nline ''
        Nline "## Final Y.42 cycle"
        Nline ""
        Nline '```'
        $slice | Where-Object { $_ -match 'Y\.42 ' } | Select-Object -Last 30 | ForEach-Object { Nline $_ }
        Nline '```'
        Write-Host "[narrative] -> $narrative" -ForegroundColor Green
    } else {
        Write-Host '[narrative] no battle slice; skipped' -ForegroundColor DarkYellow
    }
} catch { Write-Host "[narrative] failed: $_" -ForegroundColor Red }

# ---------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------
Write-Host ''
Write-Host '====== Crest-Diag done. Outputs in C:\dev\bannerlord\crest\.runner\diag\ ======' -ForegroundColor Green
Get-ChildItem $diagDir -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 12 |
    ForEach-Object { Write-Host ('  {0,12:N0} bytes  {1}' -f $_.Length, $_.Name) }
