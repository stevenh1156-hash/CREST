# =====================================================================
# Crest-VerifyOrBattle.ps1 -- the smoke-test gate.
# =====================================================================
# Runs after each Ready completes. The pipeline is:
#   1. Crest-FinalSim  (replay last N recordings, write verdict)
#   2. Read .runner\diag\finalsim-verdict.txt
#   3. If verdict in {stable, minor-drift} -> chain complete, no real battle
#      If verdict in {major-drift, no-recordings} -> run Crest-AutoBattle
#
# This is the gate that lets HERALD skip an in-game battle whenever the
# rule changes don't perturb replay outcomes more than 2..10%. The user
# only has to play a real battle when FinalSim says one is warranted.
#
# Usage:
#   crest VerifyOrBattle             -- replays last 5
#   crest VerifyOrBattle -N 10       -- replays last 10
#   crest VerifyOrBattle -ForceBattle-- always run AutoBattle after sim
# =====================================================================

param(
    [int]$N = 5,
    [switch]$ForceBattle
)

$ErrorActionPreference = 'Continue'

$crestRoot   = 'C:\dev\bannerlord\crest'
$verdictPath = Join-Path $crestRoot '.runner\diag\finalsim-verdict.txt'

Write-Host ''
Write-Host '== Crest VerifyOrBattle ==' -ForegroundColor Cyan
Write-Host '  step 1: FinalSim' -ForegroundColor Gray
& (Join-Path $crestRoot 'Crest-FinalSim.ps1') -N $N | Out-Host

$verdict = ''
if (Test-Path $verdictPath) {
    $verdict = (Get-Content $verdictPath -Raw -ErrorAction SilentlyContinue).Trim()
}
Write-Host ''
Write-Host "  finalsim verdict: $verdict" -ForegroundColor Yellow

$needBattle = $ForceBattle.IsPresent -or
              ($verdict -eq 'major-drift') -or
              ($verdict -eq 'no-recordings') -or
              ($verdict -eq '')

if (-not $needBattle) {
    Write-Host '  step 2: real battle SKIPPED (FinalSim says verdict is acceptable)' -ForegroundColor Green
    Write-Host '          HERALD chain complete -- no smoke test required.' -ForegroundColor Green
    Write-Host ''
    exit 0
}

Write-Host '  step 2: AutoBattle (real in-game smoke test required)' -ForegroundColor Yellow
& (Join-Path $crestRoot 'Crest-AutoBattle.ps1')
exit $LASTEXITCODE
