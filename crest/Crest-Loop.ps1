# =====================================================================
# Crest-Loop.ps1 -- one iteration of the auto-iterate gate.
# =====================================================================
# Phase 5 of the unified Bannerlord module creator. Runs:
#   1. dotnet build <csproj>          (Release config)
#   2. Crest-Sim.ps1 (full scenario suite, optionally filtered)
#   3. writes verdict JSON: READY | NEEDS_FIX (build) | NEEDS_FIX (sim)
#
# The agent reads the verdict, decides whether to:
#   - iterate (apply a fix, re-queue Crest-Loop.ps1)
#   - hand off to user for in-game testing ("ready to test, say done when finished")
#
# Verdict file: .runner\loop\verdict-<stamp>.json
# Build log:    .runner\loop\build-<stamp>.txt
# Sim log:      .runner\loop\sim-<stamp>.txt
#
# Usage:
#   & C:\dev\bannerlord\crest\Crest-Loop.ps1
#       -CsprojPath C:\dev\bannerlord\Bannerlord.WeatherSystem\src\Crest.WeatherSystem\Crest.WeatherSystem.csproj
#
#   # default target: the most-recently-scaffolded Bannerlord.* module's csproj
#   & C:\dev\bannerlord\crest\Crest-Loop.ps1
#
#   # only run a specific sim scenario
#   & C:\dev\bannerlord\crest\Crest-Loop.ps1 -Scenario weather-rain-archer-penalty
# =====================================================================

param(
    [string]$CsprojPath = '',
    [string]$Scenario   = '',
    [switch]$SkipBuild,
    [switch]$SkipSim
)

$ErrorActionPreference = 'Continue'

$crestRoot = 'C:\dev\bannerlord\crest'
$loopDir   = Join-Path $crestRoot '.runner\loop'
New-Item -ItemType Directory -Path $loopDir -Force | Out-Null

$stamp       = (Get-Date).ToString('yyyyMMdd-HHmmss')
$verdictPath = Join-Path $loopDir "verdict-$stamp.json"
$buildLog    = Join-Path $loopDir "build-$stamp.txt"
$simLog      = Join-Path $loopDir "sim-$stamp.txt"

Write-Host '== Crest-Loop ==' -ForegroundColor Cyan

# --- Resolve target csproj ---
if (-not $CsprojPath) {
    # Find most-recently-modified csproj under C:\dev\bannerlord\Bannerlord.*\src\Crest.*\
    $candidates = Get-ChildItem 'C:\dev\bannerlord' -Directory -Filter 'Bannerlord.*' -ErrorAction SilentlyContinue |
                  ForEach-Object {
                      Get-ChildItem (Join-Path $_.FullName 'src') -Directory -Filter 'Crest.*' -ErrorAction SilentlyContinue |
                      ForEach-Object {
                          Get-ChildItem $_.FullName -Filter '*.csproj' -File -ErrorAction SilentlyContinue
                      }
                  }
    $latest = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) {
        $CsprojPath = $latest.FullName
        Write-Host "  auto-detected csproj: $CsprojPath" -ForegroundColor DarkGray
    } else {
        Write-Host '  ERROR: no -CsprojPath given and no Bannerlord.*\src\Crest.*\*.csproj found' -ForegroundColor Red
        $verdict = [pscustomobject]@{
            stamp        = $stamp
            status       = 'NEEDS_FIX'
            stage        = 'precheck'
            reason       = 'no csproj target'
            csprojPath   = ''
            buildOk      = $false
            simOk        = $false
            generatedAt  = (Get-Date).ToString('o')
        }
        $verdict | ConvertTo-Json -Depth 5 | Set-Content -Path $verdictPath -Encoding utf8
        exit 1
    }
}

if (-not (Test-Path $CsprojPath)) {
    Write-Host "  ERROR: csproj not found: $CsprojPath" -ForegroundColor Red
    exit 1
}
$modName = ([System.IO.Path]::GetFileNameWithoutExtension($CsprojPath)) -replace '^Crest\.',''
Write-Host "  target:    $modName"
Write-Host "  csproj:    $CsprojPath"

# --- 1. Build ---
$buildOk      = $true
$buildErrors  = @()
$buildWarnings = 0

if ($SkipBuild) {
    Write-Host '  [1/2] BUILD skipped (-SkipBuild)' -ForegroundColor DarkGray
} else {
    Write-Host '  [1/2] BUILD' -ForegroundColor Cyan
    $buildArgs = @(
        'build', "`"$CsprojPath`""
        '-c','Release'
        '/nologo'
        '/clp:Summary;NoItemAndPropertyList'
    )
    $proc = Start-Process -FilePath 'dotnet' -ArgumentList $buildArgs `
                          -NoNewWindow -PassThru -Wait `
                          -RedirectStandardOutput $buildLog `
                          -RedirectStandardError "$buildLog.err"
    if (Test-Path "$buildLog.err") {
        Add-Content -Path $buildLog -Value (Get-Content "$buildLog.err" -Raw)
        Remove-Item "$buildLog.err" -Force -ErrorAction SilentlyContinue
    }
    $buildOk = ($proc.ExitCode -eq 0)

    # Parse errors out of the log (msbuild "error CSxxxx:" lines).
    if (Test-Path $buildLog) {
        $buildErrors = Select-String -Path $buildLog -Pattern '\):\s*error\s+\w+\d+:' -SimpleMatch:$false |
                       ForEach-Object { $_.Line.Trim() } | Select-Object -First 20
        $buildWarnings = (Select-String -Path $buildLog -Pattern '\):\s*warning\s+\w+\d+:' -SimpleMatch:$false).Count
    }

    if ($buildOk) {
        Write-Host "        OK  ($buildWarnings warnings)" -ForegroundColor Green
    } else {
        Write-Host "        FAIL  ($($buildErrors.Count) errors, $buildWarnings warnings)" -ForegroundColor Red
        foreach ($e in ($buildErrors | Select-Object -First 5)) {
            Write-Host "          $e" -ForegroundColor Red
        }
        if ($buildErrors.Count -gt 5) { Write-Host "          ... + $($buildErrors.Count - 5) more (see $buildLog)" -ForegroundColor DarkRed }
    }
}

# --- 2. Sim (only if build OK or build skipped) ---
$simOk     = $true
$simReason = ''
$simStats  = $null

if ($SkipSim) {
    Write-Host '  [2/2] SIM skipped (-SkipSim)' -ForegroundColor DarkGray
} elseif (-not $buildOk) {
    Write-Host '  [2/2] SIM skipped (build failed)' -ForegroundColor DarkGray
    $simOk = $false
    $simReason = 'build-failed-prerequisite'
} else {
    Write-Host '  [2/2] SIM' -ForegroundColor Cyan
    $simScript = Join-Path $crestRoot 'Crest-Sim.ps1'
    $simArgs = @{}
    if ($Scenario) { $simArgs.Scenario = $Scenario }

    # Run sim, redirect to log, capture exit code.
    try {
        & $simScript @simArgs *> $simLog
        $simExit = $LASTEXITCODE
    } catch {
        $simExit = 99
        Add-Content -Path $simLog -Value "EXCEPTION: $($_.Exception.Message)"
    }
    $simOk = ($simExit -eq 0)

    # Extract pass/fail counts from log (Crest-Sim prints "passed: N / N").
    if (Test-Path $simLog) {
        $passLine = Select-String -Path $simLog -Pattern 'passed:\s*\d+' -SimpleMatch:$false | Select-Object -First 1
        if ($passLine) { $simStats = $passLine.Line.Trim() }
    }

    if ($simOk) {
        Write-Host "        OK  $simStats" -ForegroundColor Green
    } else {
        Write-Host "        FAIL  exit=$simExit  $simStats" -ForegroundColor Red
        $simReason = "sim exit $simExit"
        # Show first failing scenario if log contains "FAIL"
        $firstFail = Select-String -Path $simLog -Pattern '^\s*FAIL\b' -SimpleMatch:$false | Select-Object -First 3
        foreach ($l in $firstFail) { Write-Host "          $($l.Line.Trim())" -ForegroundColor Red }
    }
}

# --- 3. Verdict ---
$status = if ($buildOk -and $simOk) { 'READY' } else { 'NEEDS_FIX' }
$stage  = if (-not $buildOk) { 'build' } elseif (-not $simOk) { 'sim' } else { 'pass' }

$verdict = [pscustomobject]@{
    stamp          = $stamp
    status         = $status
    stage          = $stage
    target         = $modName
    csprojPath     = $CsprojPath
    buildOk        = $buildOk
    buildWarnings  = $buildWarnings
    buildErrors    = $buildErrors
    buildLog       = $buildLog
    simOk          = $simOk
    simReason      = $simReason
    simStats       = $simStats
    simLog         = $simLog
    generatedAt    = (Get-Date).ToString('o')
}
$verdict | ConvertTo-Json -Depth 8 | Set-Content -Path $verdictPath -Encoding utf8

# Also write a pointer at .runner\loop\latest.json so the agent doesn't
# need to globe through timestamps to find the most recent verdict.
$latestPath = Join-Path $loopDir 'latest.json'
$verdict | ConvertTo-Json -Depth 8 | Set-Content -Path $latestPath -Encoding utf8

Write-Host ''
Write-Host "  verdict: $status  (stage: $stage)" -ForegroundColor $(if ($status -eq 'READY') { 'Green' } else { 'Yellow' })
Write-Host "    written: $verdictPath" -ForegroundColor DarkGray
Write-Host "    pointer: $latestPath"  -ForegroundColor DarkGray
Write-Host ''
if ($status -eq 'READY') {
    Write-Host '  AGENT INSTRUCTIONS:'
    Write-Host '    Build is clean and sim regression suite is green.' -ForegroundColor Gray
    Write-Host '    Tell the user: "deploy is ready -- test in-game and say done when finished".' -ForegroundColor Gray
} else {
    Write-Host '  AGENT INSTRUCTIONS:'
    Write-Host "    Loop FAILED at stage: $stage." -ForegroundColor Gray
    Write-Host '    1. Read the build/sim log paths in the verdict JSON.' -ForegroundColor Gray
    Write-Host '    2. Apply a targeted fix.' -ForegroundColor Gray
    Write-Host '    3. Re-queue Crest-Loop.ps1 (or Crest.ps1 -Mode Loop).'  -ForegroundColor Gray
}
Write-Host ''

# Exit code mirrors verdict so the watcher's result.json shows pass/fail clearly.
if ($status -eq 'READY') { exit 0 } else { exit 1 }
