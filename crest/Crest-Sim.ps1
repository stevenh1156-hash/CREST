# =====================================================================
# Crest-Sim : run the Y.54 / Y.56 rule logic against synthetic battle
# scenarios without launching Bannerlord.
# =====================================================================
# Usage:
#   & C:\dev\bannerlord\crest\Crest-Sim.ps1
#   & C:\dev\bannerlord\crest\Crest-Sim.ps1 -Scenario 01-wandering-archers
#   & C:\dev\bannerlord\crest\Crest-Sim.ps1 -ShowLog
#
# What this does:
#   1. Builds Crest.Harmony.Sim (and the rules-side of Crest.Harmony) once
#   2. Runs every JSON scenario in sim\scenarios\ (or just the named one)
#   3. Each scenario produces Y.42-format log lines AND assertion checks
#      (each formation can declare expectAction = "wander-clamp" / "none" /
#      etc., and the sim fails if the rule decision doesn't match)
#   4. Final output goes to .runner\sim-output\runtime.log so Crest-Diag
#      can be pointed at it for narrative + battle-summary parsing
#   5. With -ShowLog, prints the full sim log at the end
#
# Cycle time: ~3-5 seconds total for all scenarios. Compare to ~5 minutes
# per real Bannerlord battle.
# =====================================================================

param(
    [string]$Scenario = "",
    [switch]$ShowLog,
    [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'

$simProj    = 'C:\dev\bannerlord\Bannerlord.Harmony\sim\Crest.Harmony.Sim\Crest.Harmony.Sim.csproj'
$simBinDir  = 'C:\dev\bannerlord\Bannerlord.Harmony\sim\Crest.Harmony.Sim\bin\Release\net472'
$simExe     = Join-Path $simBinDir 'Crest.Harmony.Sim.exe'
$scenarios  = 'C:\dev\bannerlord\Bannerlord.Harmony\sim\Crest.Harmony.Sim\scenarios'
$outDir     = 'C:\dev\bannerlord\crest\.runner\sim-output'
$outLog     = Join-Path $outDir 'runtime.log'

New-Item -ItemType Directory -Path $outDir -Force | Out-Null

if (-not $NoBuild) {
    Write-Host '== build Crest.Harmony.Sim ==' -ForegroundColor Cyan
    $buildOut = & dotnet build $simProj -c Release 2>&1 | Out-String
    Write-Host $buildOut
    if ($LASTEXITCODE -ne 0) {
        # NETSDK1005 = assets file is stale or missing the requested target framework.
        # Almost always caused by a previous failed multi-targeting attempt that
        # left obj/ in a bad state. Nuke obj/+bin/ and retry once -- if that
        # works, the user never has to think about it.
        if ($buildOut -match 'NETSDK1005') {
            Write-Host '[sim] NETSDK1005 detected -- clearing stale obj/bin and retrying' -ForegroundColor Yellow
            $simDir = Split-Path $simProj -Parent
            Remove-Item -Recurse -Force (Join-Path $simDir 'obj'), (Join-Path $simDir 'bin') -ErrorAction SilentlyContinue
            & dotnet build $simProj -c Release 2>&1 | Out-String | Write-Host
        }
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "BUILD FAILED (exit=$LASTEXITCODE)" -ForegroundColor Red
        exit 1
    }
}

if (-not (Test-Path $simExe)) {
    Write-Host "sim exe not found: $simExe" -ForegroundColor Red
    Write-Host "(run without -NoBuild to compile it first)" -ForegroundColor DarkGray
    exit 1
}

# Pick input: single scenario file, or whole directory.
$input = $scenarios
if ($Scenario) {
    $candidate = Join-Path $scenarios "$Scenario.json"
    if (-not (Test-Path $candidate)) {
        Write-Host "scenario not found: $candidate" -ForegroundColor Red
        Write-Host "available:" -ForegroundColor DarkGray
        Get-ChildItem $scenarios -Filter '*.json' | ForEach-Object {
            Write-Host "  $($_.BaseName)" -ForegroundColor DarkGray
        }
        exit 1
    }
    $input = $candidate
}

Write-Host ''
Write-Host '== running scenarios ==' -ForegroundColor Cyan
# net472 produces a native exe -- invoke directly, no dotnet wrapper.
& $simExe $input $outLog
$exit = $LASTEXITCODE

Write-Host ''
if ($exit -eq 0) {
    Write-Host "[ok] all scenarios passed -- log at $outLog" -ForegroundColor Green
} else {
    Write-Host "[fail] sim returned exit=$exit -- see assertion failures above" -ForegroundColor Red
}

if ($ShowLog -and (Test-Path $outLog)) {
    Write-Host ''
    Write-Host '== sim runtime.log ==' -ForegroundColor Cyan
    Get-Content $outLog
}

exit $exit
