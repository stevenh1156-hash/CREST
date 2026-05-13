# Phase T build runner.
# Builds Crest.Harmony (with the new CrestCheats sub-module) and Crest.MCM.UI
# (with the new "Enable Bannerlord cheats" MCM toggle), hot-swaps both DLLs,
# and restores the full bundle's other DLLs from crest/dist/CREST/ since
# -Clean wipes the deployed bundle down to just the rebuilt repo's output.

$ErrorActionPreference = 'Stop'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$deployedBin = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'
$bundleSrcBin = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client'

function Verify-Copy {
    param([string]$Src, [string]$Dst)
    [IO.File]::Copy($Src, $Dst, $true)
    $s = (Get-Item $Src).Length
    $d = (Get-Item $Dst).Length
    if ($s -ne $d) { throw "Copy size mismatch for $Dst (src=$s dst=$d)" }
}

Write-Host "==> [1/4] Rebuilding Crest.Harmony with CrestCheats..." -ForegroundColor Cyan
$ok = Build-CrestRepo -Name Harmony -Clean
if (-not $ok) { Write-Host "Crest.Harmony build failed" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "==> [2/4] Rebuilding Crest.MCM (incl. UI with new Cheats toggle)..." -ForegroundColor Cyan
$ok = Build-CrestRepo -Name MCM -Clean
if (-not $ok) { Write-Host "Crest.MCM build failed" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "==> [3/4] Restoring full bundle from crest/dist/CREST/" -ForegroundColor Cyan
# Get-Item on each dist DLL, copy to deployedBin. Skip files already present
# with matching size+mtime to avoid pointless writes.
$copied = 0
Get-ChildItem -Path $bundleSrcBin -Filter '*.dll' | ForEach-Object {
    $dst = Join-Path $deployedBin $_.Name
    if (-not (Test-Path $dst) -or ((Get-Item $dst).Length -ne $_.Length)) {
        Verify-Copy $_.FullName $dst
        $copied++
    }
}
Write-Host ("    restored $copied DLL(s) from full bundle.") -ForegroundColor Green

# Heal the deployed SubModule.xml from the full bundle template (NOT from the
# Crest.Harmony per-repo template, which would leave only one SubModule entry).
$xmlSrc = 'C:\dev\bannerlord\crest\dist\CREST\SubModule.xml'
$xmlDst = Join-Path $gameRoot 'Modules\CREST\SubModule.xml'
[IO.File]::WriteAllText($xmlDst, [IO.File]::ReadAllText($xmlSrc))
Write-Host "    healed deployed SubModule.xml from full bundle" -ForegroundColor Green

Write-Host ""
Write-Host "==> [4/4] Overlaying freshly-built Crest.Harmony.dll and CREST.v1.4.1.dll" -ForegroundColor Cyan
$harmonySrc = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll'
Verify-Copy $harmonySrc (Join-Path $deployedBin 'Crest.Harmony.dll')
$harmonyLen = (Get-Item $harmonySrc).Length
Write-Host ("    Crest.Harmony.dll ($harmonyLen bytes) overlaid -- new build with CrestCheats") -ForegroundColor Green

# Crest.MCM.UI's compiled output is named CREST.v1.4.1.dll due to BUTRModule SDK
# version-baked filename. Find the most recent build under Crest.MCM.UI.
$uiSrc = Get-ChildItem -Path 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI' `
    -Recurse -File -Filter 'CREST.v*.dll' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\bin\\.*Release\\' -and $_.FullName -notmatch '\\obj\\' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($uiSrc) {
    Verify-Copy $uiSrc.FullName (Join-Path $deployedBin $uiSrc.Name)
    Write-Host ("    " + $uiSrc.Name + " (" + $uiSrc.Length + " bytes) overlaid -- new build with Cheats toggle") -ForegroundColor Green
} else {
    Write-Host "    WARNING: CREST.v*.dll not found in Crest.MCM.UI build output -- the new MCM toggle won't appear in-game" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==> Phase T deploy done." -ForegroundColor Green
Write-Host "    The 'Cheats' flag in crest.json is currently OFF. Two ways to enable:" -ForegroundColor White
Write-Host "      (a) Edit Modules\CREST\crest.json: set ""Cheats"": true; relaunch." -ForegroundColor White
Write-Host "      (b) In-game: Mod Options -> CREST -> Cheats group -> 'Enable Bannerlord cheats'; relaunch." -ForegroundColor White
Write-Host "    Either path writes cheat_mode = 1 to engine_config.txt on next launch." -ForegroundColor White
exit 0
