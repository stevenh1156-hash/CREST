# Phase X — restore deployed bundle + stub bin folders.
#
# After Phase W's MCM rebuild, the BUTRModule SDK auto-deploy stripped the
# deployed Modules/CREST/bin/Win64_Shipping_Client/ down to just the rebuilt
# DLLs. This restores the full bundle from crest/dist/CREST/, then populates
# each Bannerlord.X stub's bin folder with the canonical DLL BLSE looks for
# (so "Can't find 0Harmony.dll in Bannerlord.Harmony" etc. stops firing).

$ErrorActionPreference = 'Stop'
$gameRoot   = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$crestDst   = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'
$crestSrc   = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client'

Write-Host "==> [1/3] Restoring full CREST bundle from $crestSrc -> $crestDst" -ForegroundColor Cyan
if (-not (Test-Path $crestSrc)) { Write-Host "FAIL: dist source not found at $crestSrc" -ForegroundColor Red; exit 1 }
$copied = 0
Get-ChildItem -Path $crestSrc -Filter '*.dll' -File | ForEach-Object {
    $dst = Join-Path $crestDst $_.Name
    if (-not (Test-Path $dst) -or (Get-Item $dst).Length -ne $_.Length) {
        try {
            [IO.File]::Copy($_.FullName, $dst, $true)
            $copied++
        } catch {
            Write-Host ("    WARN: " + $_.Name + " copy failed: " + $_.Exception.Message) -ForegroundColor Yellow
        }
    }
}
$total = (Get-ChildItem $crestDst -File | Measure-Object).Count
Write-Host ("    restored $copied DLL(s); deployed bundle now has $total files") -ForegroundColor Green

# Heal the bundle's SubModule.xml. Every time a Crest.* repo is rebuilt, the
# BUTRModule SDK's auto-deploy step writes that repo's per-module
# _Module/SubModule.xml template (with $moduleid$ substituted to "CREST")
# over the deployed Modules/CREST/SubModule.xml -- collapsing the 8-entry
# bundle xml down to a single per-repo xml. Symptom: the launcher displays
# CREST as "CREST UIExtenderEx" or similar and only one of CREST's sub-
# modules actually loads. Restore from the canonical bundle xml in dist.
$xmlSrc = Join-Path (Split-Path -Parent $crestSrc) 'SubModule.xml'    # dist/CREST/SubModule.xml (one level up from dist/CREST/bin/...)
# Actually crestSrc is dist/CREST/bin/Win64_Shipping_Client; xml is two levels up.
$xmlSrc = Resolve-Path (Join-Path $crestSrc '..\..\SubModule.xml') -ErrorAction SilentlyContinue
$xmlDst = Join-Path $gameRoot 'Modules\CREST\SubModule.xml'
if ($xmlSrc -and (Test-Path $xmlSrc)) {
    [IO.File]::Copy($xmlSrc, $xmlDst, $true)
    Write-Host ("    healed bundle SubModule.xml from " + $xmlSrc) -ForegroundColor Green
} else {
    Write-Host ("    WARN: dist SubModule.xml not found; deployed bundle xml left as-is") -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==> [2/3] Populating stub bin folders with canonical DLLs" -ForegroundColor Cyan
# Each stub gets the FULL set of DLLs upstream BUTR ships in that module's
# bin folder. BLSE's HarmonyFinder validates the Bannerlord.Harmony module by
# checking for every Harmony-related dependency (0Harmony.dll, Mono.Cecil.dll
# and friends, MonoMod.*) and bombs out with "The Harmony module is corrupted!"
# the moment any one is missing. Same shape applies to the other 3 stubs:
# we mirror the canonical upstream layout into each.
$stubFiles = @{
    'Bannerlord.Harmony' = @(
        '0Harmony.dll',
        'Mono.Cecil.dll', 'Mono.Cecil.Mdb.dll', 'Mono.Cecil.Pdb.dll', 'Mono.Cecil.Rocks.dll',
        'MonoMod.Backports.dll', 'MonoMod.Core.dll', 'MonoMod.Iced.dll',
        'MonoMod.ILHelpers.dll', 'MonoMod.Utils.dll'
    )
    'Bannerlord.ButterLib' = @(
        'Bannerlord.ButterLib.dll',
        'Microsoft.Bcl.HashCode.dll',
        'Serilog.dll', 'Serilog.Extensions.Logging.dll', 'Serilog.Sinks.File.dll'
    )
    'Bannerlord.UIExtenderEx' = @(
        'Bannerlord.UIExtenderEx.dll'
    )
    'Bannerlord.MBOptionScreen' = @(
        'MCMv5.dll'
    )
}
foreach ($stub in $stubFiles.Keys) {
    $dstDir = Join-Path $gameRoot ('Modules\' + $stub + '\bin\Win64_Shipping_Client')
    if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Force -Path $dstDir | Out-Null }
    $copied = 0
    $missing = 0
    foreach ($dll in $stubFiles[$stub]) {
        $src = Join-Path $crestDst $dll
        $dst = Join-Path $dstDir $dll
        if (-not (Test-Path $src)) { $missing++; continue }
        try {
            [IO.File]::Copy($src, $dst, $true)
            $copied++
        } catch {
            Write-Host ("    WARN: $stub $dll copy failed: " + $_.Exception.Message) -ForegroundColor Yellow
        }
    }
    Write-Host ("    ${stub}: copied $copied DLL(s)" + $(if ($missing -gt 0) { ", $missing missing" } else { "" })) -ForegroundColor Green
}

Write-Host ""
Write-Host "==> [3/3] Quick health check" -ForegroundColor Cyan
foreach ($f in '0Harmony.dll', 'Crest.Harmony.dll', 'Bannerlord.Harmony.dll', 'MCMv5.dll', 'CREST.v1.4.1.dll') {
    $p = Join-Path $crestDst $f
    if (Test-Path $p) { Write-Host ("    OK $f") -ForegroundColor Green }
    else              { Write-Host ("    MISSING $f") -ForegroundColor Red }
}
foreach ($stub in $stubMap.Keys) {
    $p = Join-Path $gameRoot ('Modules\' + $stub + '\bin\Win64_Shipping_Client\' + $stubMap[$stub])
    if (Test-Path $p) { Write-Host ("    OK $stub/bin/" + $stubMap[$stub]) -ForegroundColor Green }
    else              { Write-Host ("    MISSING $stub/bin/" + $stubMap[$stub]) -ForegroundColor Red }
}

Write-Host ""
Write-Host "==> Done. Launch the game; the 'Harmony module is corrupted' error should be gone." -ForegroundColor Green
exit 0
