# Phase W.2 — force-clean rebuild of Crest.Harmony + Crest.MCM, then deploy
# the fresh DLLs into both the live install AND the dist folder so a future
# Phase X restore doesn't clobber them.

$ErrorActionPreference = 'Stop'
$gameRoot   = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$crestDst   = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'
$distDst    = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client'

function Force-Clean {
    param([string]$RepoRoot)
    Get-ChildItem $RepoRoot -Recurse -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @('bin','obj') } |
        ForEach-Object {
            try { Remove-Item -Recurse -Force $_.FullName } catch { }
        }
}

function Verify-Copy {
    param([string]$Src, [string]$DstFile)
    if (-not (Test-Path $Src)) { Write-Host ("    SKIP missing src: " + $Src) -ForegroundColor Yellow; return }
    [IO.File]::Copy($Src, $DstFile, $true)
    if ((Get-Item $Src).Length -ne (Get-Item $DstFile).Length) {
        throw "Copy size mismatch for $DstFile"
    }
    Write-Host ("    " + (Split-Path $Src -Leaf) + " -> " + (Split-Path $DstFile -Parent) + " (" + (Get-Item $Src).Length + " bytes)") -ForegroundColor Green
}

Write-Host "==> [1/4] Force-cleaning bin/obj for Crest.Harmony" -ForegroundColor Cyan
Force-Clean 'C:\dev\bannerlord\Bannerlord.Harmony\src'

Write-Host "==> [2/4] Force-cleaning bin/obj for Crest.MCM (core + UI + adapter)" -ForegroundColor Cyan
Force-Clean 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src'
Force-Clean 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui'

Write-Host ""
Write-Host "==> [3/4] dotnet build (no-incremental this time, fresh trees)" -ForegroundColor Cyan
Push-Location 'C:\dev\bannerlord\Bannerlord.Harmony'
try {
    Write-Host "  building Crest.Harmony..." -ForegroundColor DarkCyan
    & dotnet build src/Crest.Harmony/Crest.Harmony.csproj -c Release --nologo -v minimal 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "  Crest.Harmony build FAILED" -ForegroundColor Red; exit 1 }
    Write-Host "  ok" -ForegroundColor Green
} finally { Pop-Location }

Push-Location 'C:\dev\bannerlord\Bannerlord.MBOptionScreen'
try {
    Write-Host "  building Crest.MCM (core)..." -ForegroundColor DarkCyan
    & dotnet build src/Crest.MCM/Crest.MCM.csproj -c Release '-p:OverrideGameVersion=v1.4.1' '-p:GameVersionConstant=v141' --nologo -v minimal 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "  Crest.MCM build FAILED" -ForegroundColor Red; exit 1 }
    Write-Host "  ok" -ForegroundColor Green

    Write-Host "  building Crest.MCM.UI..." -ForegroundColor DarkCyan
    & dotnet build src-ui/Crest.MCM.UI/Crest.MCM.UI.csproj -c Stable_Release '-p:OverrideGameVersion=v1.4.1' '-p:GameVersionConstant=v141' '-p:ExtendedBuild=false' --nologo -v minimal 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "  Crest.MCM.UI build FAILED" -ForegroundColor Red; exit 1 }
    Write-Host "  ok" -ForegroundColor Green
} finally { Pop-Location }

Write-Host ""
Write-Host "==> [4/4] Deploying fresh DLLs into both deployed bundle AND dist" -ForegroundColor Cyan

# Find the freshest source-side build artifacts
$harmony = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll'
# Match both 'Release' and 'Stable_Release' (and similar) build configs by
# anchoring on '\bin\' and excluding obj/. The MCM.UI csproj uses
# Stable_Release config which my prior '\\Release\\' regex didn't match,
# so CREST.v*.dll silently skipped deployment.
$mcmCore = Get-ChildItem 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src\Crest.MCM\bin' -Recurse -File -Filter 'Crest.MCM.dll' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\obj\\' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$mcmUi = Get-ChildItem 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI\bin' -Recurse -File -Filter 'CREST.v*.dll' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\obj\\' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

# Deploy to live bundle
Verify-Copy $harmony      (Join-Path $crestDst 'Crest.Harmony.dll')
if ($mcmCore) { Verify-Copy $mcmCore.FullName (Join-Path $crestDst 'Crest.MCM.dll') }
if ($mcmUi)   { Verify-Copy $mcmUi.FullName   (Join-Path $crestDst $mcmUi.Name) }

# Mirror into dist so future fresh-installs / Phase X restores include the new code
Verify-Copy $harmony      (Join-Path $distDst 'Crest.Harmony.dll')
if ($mcmCore) { Verify-Copy $mcmCore.FullName (Join-Path $distDst 'Crest.MCM.dll') }
if ($mcmUi)   { Verify-Copy $mcmUi.FullName   (Join-Path $distDst $mcmUi.Name) }

Write-Host ""
Write-Host "==> Done. Launch the game; MCM CREST should now show the 6 new" -ForegroundColor Green
Write-Host "    'Campaign log filter' toggles (Skill / Hero events / Relation /" -ForegroundColor White
Write-Host "    Kingdom / Minor battles / Quests)." -ForegroundColor White
exit 0
