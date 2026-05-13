# Phase W — build + deploy the campaign-log filter.
# Rebuilds Crest.Harmony (patch logic + new flags in CrestConfig defaults)
# and Crest.MCM (CrestSettings UI toggles).

$ErrorActionPreference = 'Stop'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

$gameRoot    = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$deployedBin = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'

Write-Host "==> [1/3] Rebuilding Crest.Harmony" -ForegroundColor Cyan
$ok = Build-CrestRepo -Name Harmony -Clean
if (-not $ok) { Write-Host "Crest.Harmony build failed" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "==> [2/3] Rebuilding Crest.MCM (incl. UI toggles)" -ForegroundColor Cyan
$ok = Build-CrestRepo -Name MCM -Clean
if (-not $ok) { Write-Host "Crest.MCM build failed" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "==> [3/3] Hot-swapping built DLLs into deployed bundle" -ForegroundColor Cyan

function Verify-Copy {
    param([string]$Src, [string]$Dst)
    if (-not (Test-Path $Src)) { Write-Host ("    SKIP missing src: " + $Src) -ForegroundColor Yellow; return }
    [IO.File]::Copy($Src, $Dst, $true)
    if ((Get-Item $Src).Length -ne (Get-Item $Dst).Length) {
        throw "Copy size mismatch for $Dst -- is the game running?"
    }
    Write-Host ("    " + (Split-Path $Src -Leaf) + " -> deployed (" + (Get-Item $Src).Length + " bytes)") -ForegroundColor Green
}

# Crest.Harmony.dll (the patch logic)
Verify-Copy `
    'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll' `
    (Join-Path $deployedBin 'Crest.Harmony.dll')

# Crest.MCM.dll (settings round-trip)
$mcmCore = Get-ChildItem -Path 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src\Crest.MCM\bin' `
    -Recurse -File -Filter 'Crest.MCM.dll' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\Release\\' -and $_.FullName -notmatch '\\obj\\' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($mcmCore) { Verify-Copy $mcmCore.FullName (Join-Path $deployedBin 'Crest.MCM.dll') }

# CREST.v*.dll (UI -- carries the new MCM toggle attributes)
$mcmUi = Get-ChildItem -Path 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI\bin' `
    -Recurse -File -Filter 'CREST.v*.dll' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\Release\\' -and $_.FullName -notmatch '\\obj\\' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($mcmUi) { Verify-Copy $mcmUi.FullName (Join-Path $deployedBin $mcmUi.Name) }

# Also stage the v1.4.x mirror in dist
$distBin = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client'
foreach ($name in @('Crest.Harmony.dll', 'Crest.MCM.dll')) {
    $p = Join-Path $deployedBin $name
    if (Test-Path $p) { [IO.File]::Copy($p, (Join-Path $distBin $name), $true) }
}
if ($mcmUi) { [IO.File]::Copy($mcmUi.FullName, (Join-Path $distBin $mcmUi.Name), $true) }

Write-Host ""
Write-Host "==> Phase W deploy done." -ForegroundColor Green
Write-Host "    Launch the game; then in Mod Options -> CREST scroll to" -ForegroundColor White
Write-Host "    'Campaign log filter' for the 6 new toggles." -ForegroundColor White
Write-Host "    Default behavior preserves all messages -- toggle individual" -ForegroundColor White
Write-Host "    buckets OFF to mute. Takes effect immediately on Save." -ForegroundColor White
exit 0
