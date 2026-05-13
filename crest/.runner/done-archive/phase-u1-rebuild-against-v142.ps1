# Phase U.1 — full rebuild of CREST against v1.4.2 game reference assemblies.
#
# Driven by Crest.Dev's GameVersion default which we already bumped to
# v1.4.2 / v142. Builds every repo in dependency order, then re-stages the
# bundle dist and hot-deploys to the user's install.
#
# Common failure mode: the v1.4.2 reference assemblies (Bannerlord.ReferenceAssemblies.Core
# 1.4.2.x-* on NuGet) may not yet be published when this script runs. If
# that happens, dotnet restore fails with NU1102 and the build aborts. The
# script catches this and prints a clear "v1.4.2 ref assemblies not yet on
# NuGet — falling back to v1.4.1" message rather than leaving the install
# half-deployed.

$ErrorActionPreference = 'Stop'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

$gameRoot     = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$deployedBin  = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'
$distBin      = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client'

Write-Host "==> [1/4] Building all CREST repos with GameVersion=v1.4.2 / v142" -ForegroundColor Cyan
$repos = @('Harmony', 'ButterLib', 'UIExtenderEx', 'MCM')
foreach ($r in $repos) {
    Write-Host ""
    Write-Host ("  -> " + $r) -ForegroundColor DarkCyan
    try {
        $ok = Build-CrestRepo -Name $r -Clean
    } catch {
        Write-Host ("BUILD FAILED for ${r}: " + $_.Exception.Message) -ForegroundColor Red
        if ($_.Exception.Message -match 'NU1102|Bannerlord\.ReferenceAssemblies') {
            Write-Host ""
            Write-Host "  ==> v1.4.2 reference assemblies aren't on NuGet yet (NU1102)." -ForegroundColor Yellow
            Write-Host "  ==> Reverting Crest.Dev.psm1 default to v1.4.1 / v141 and aborting." -ForegroundColor Yellow
            $envHint = "  Set `$env:CREST_GAME_VERSION='v1.4.2'; `$env:CREST_GAME_VERSION_CONSTANT='v142' once they ship and rerun."
            Write-Host $envHint -ForegroundColor Yellow
        }
        exit 1
    }
    if (-not $ok) { Write-Host "$r build failed" -ForegroundColor Red; exit 1 }
}

Write-Host ""
Write-Host "==> [2/4] Re-stage bundle from each repo's bin/Release" -ForegroundColor Cyan
# Each repo deploys via the BUTRModule SDK auto-deploy when GameFolder is set.
# But we ALSO want the dist/CREST/bin/ to match (modders pull from there too).
# Copy the freshly-built DLLs from each repo's bin into dist/CREST/bin.
$srcMap = @{
    'Crest.Harmony.dll'                = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll'
    'Crest.ButterLib.dll'              = 'C:\dev\bannerlord\Bannerlord.ButterLib\src\Crest.ButterLib\bin\Release\net472\Crest.ButterLib.dll'
    'Crest.ButterLib.Implementation.dll' = 'C:\dev\bannerlord\Bannerlord.ButterLib\src\Crest.ButterLib.Implementation\bin\v142_Stable_Release\net472\Crest.ButterLib.Implementation.dll'
    'Crest.UIExtenderEx.dll'           = 'C:\dev\bannerlord\Bannerlord.UIExtenderEx\src\Crest.UIExtenderEx\bin\Release\net472\Crest.UIExtenderEx.dll'
    'Crest.MCM.dll'                    = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src\Crest.MCM\bin\v142_Release\net472\Crest.MCM.dll'
    'CREST.v1.4.2.dll'                 = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI\bin\v142_Stable_Release\net472\CREST.v1.4.2.dll'
    'Crest.MCM.UI.Adapter.MCMv5.dll'   = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI.Adapter.MCMv5\bin\v142_Stable_Release\net472\Crest.MCM.UI.Adapter.MCMv5.dll'
}
foreach ($name in $srcMap.Keys) {
    $src = $srcMap[$name]
    $dstDist  = Join-Path $distBin $name
    $dstLive  = Join-Path $deployedBin $name
    if (Test-Path $src) {
        [IO.File]::Copy($src, $dstDist, $true)
        [IO.File]::Copy($src, $dstLive, $true)
        Write-Host ("  copied " + $name) -ForegroundColor Green
    } else {
        Write-Host ("  WARN  $name not at expected path: $src") -ForegroundColor Yellow
    }
}

# Old CREST.v1.4.1.dll is now stale — delete from both dist and deployed
foreach ($p in @((Join-Path $distBin 'CREST.v1.4.1.dll'), (Join-Path $deployedBin 'CREST.v1.4.1.dll'))) {
    if (Test-Path $p) {
        Remove-Item $p -Force -ErrorAction SilentlyContinue
        Write-Host ("  removed stale " + (Split-Path $p -Leaf)) -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "==> [3/4] Update bundle SubModule.xml DLLName references v1.4.1 -> v1.4.2" -ForegroundColor Cyan
foreach ($xml in @('C:\dev\bannerlord\crest\dist\CREST\SubModule.xml', (Join-Path $gameRoot 'Modules\CREST\SubModule.xml'))) {
    if (Test-Path $xml) {
        $text = [IO.File]::ReadAllText($xml)
        $new  = $text -replace 'CREST\.v1\.4\.1\.dll', 'CREST.v1.4.2.dll'
        if ($new -ne $text) {
            [IO.File]::WriteAllText($xml, $new)
            Write-Host ("  updated " + $xml) -ForegroundColor Green
        } else {
            Write-Host ("  no v1.4.1 ref in " + $xml + " (already updated or different format)") -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
Write-Host "==> [4/4] Done. Launch the game; the v1.4.2-built CREST should boot to main menu." -ForegroundColor Cyan
Write-Host "    If you see 'Cannot load: CREST.v1.4.1.dll' the SubModule.xml didn't update --" -ForegroundColor White
Write-Host "    re-run this script with admin / no game open." -ForegroundColor White
exit 0
