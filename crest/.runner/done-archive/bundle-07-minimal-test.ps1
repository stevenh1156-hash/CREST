$ErrorActionPreference = 'Continue'

# Deploy a MINIMAL CREST: only Crest.Harmony + its native deps. No ButterLib, no UIExtenderEx, no MCM, no BEW.
# If the launcher accepts THIS, the issue is in our other components, not Harmony or the bundling itself.
# If the launcher STILL crashes, the issue is in our Harmony fork or the master SubModule.xml structure.

$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
$crestDir = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'

if (Test-Path $crestDir) {
    Write-Host "==> Wiping deployed CREST..."
    Remove-Item -Recurse -Force $crestDir
}
New-Item -ItemType Directory -Path $bin -Force | Out-Null

# Copy ONLY the Harmony-related DLLs from our staging
$source = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client'
$keep = @(
    'Crest.Harmony.dll',
    '0Harmony.dll',
    'Mono.Cecil.dll',
    'Mono.Cecil.Mdb.dll',
    'Mono.Cecil.Pdb.dll',
    'Mono.Cecil.Rocks.dll',
    'MonoMod.Core.dll',
    'MonoMod.Backports.dll',
    'MonoMod.Iced.dll',
    'MonoMod.ILHelpers.dll',
    'MonoMod.Utils.dll'
)
foreach ($n in $keep) {
    $src = Join-Path $source $n
    if (Test-Path $src) {
        Copy-Item $src -Destination $bin -Force
        Write-Host "    copied $n"
    } else {
        Write-Host "    MISSING source: $n" -ForegroundColor Red
    }
}

# Use the minimal SubModule.xml
Copy-Item 'C:\dev\bannerlord\crest\Modules\CREST\SubModule.xml.minimal' -Destination (Join-Path $crestDir 'SubModule.xml') -Force

# Verify
Write-Host ""
Write-Host "==> Minimal CREST deployment:"
Write-Host "  Root files:"
Get-ChildItem $crestDir -File | ForEach-Object { Write-Host "    $($_.Name) ($([math]::Round($_.Length/1KB,1))KB)" }
Write-Host "  bin DLLs:"
Get-ChildItem $bin -Filter '*.dll' | ForEach-Object { Write-Host "    $($_.Name)" }

Write-Host ""
Write-Host "==> READY FOR MINIMAL TEST"
Write-Host "    In launcher: tick CREST + Native only. Untick everything else."
Write-Host "    If launcher CRASHES: the issue is in Crest.Harmony or master SubModule.xml structure."
Write-Host "    If launcher WORKS: we'll add components back one at a time."
exit 0
