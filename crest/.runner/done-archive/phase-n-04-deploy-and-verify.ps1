$ErrorActionPreference = 'Continue'

Write-Host '==> Phase N deploy + verify' -ForegroundColor Cyan

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'

# ----- 1. Deploy Crest.Harmony.dll -----
Write-Host ''
Write-Host '[1/4] Deploy Crest.Harmony.dll' -ForegroundColor Cyan
$src = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll'
$dst = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client\Crest.Harmony.dll'
if (Test-Path $src) {
    Copy-Item $src $dst -Force
    $f = Get-Item $dst
    Write-Host ("  OK -> " + $dst + " (" + ([math]::Round($f.Length/1KB)) + " KB, " + $f.LastWriteTime.ToString('HH:mm:ss') + ")") -ForegroundColor Green
} else {
    Write-Host "  MISSING source $src" -ForegroundColor Red
}

# Also deploy the .pdb if present so stack traces resolve
$srcPdb = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.pdb'
$dstPdb = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client\Crest.Harmony.pdb'
if (Test-Path $srcPdb) { Copy-Item $srcPdb $dstPdb -Force; Write-Host "  + Crest.Harmony.pdb" -ForegroundColor DarkGray }

# ----- 2. Deploy Bannerlord.LauncherEx.dll -----
Write-Host ''
Write-Host '[2/4] Deploy Bannerlord.LauncherEx.dll' -ForegroundColor Cyan
$src2 = 'C:\dev\bannerlord\Bannerlord.BLSE\src\Bannerlord.LauncherEx\bin\Release_140\netstandard2.0\Bannerlord.LauncherEx.dll'
$dst2 = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.LauncherEx.dll'
if (Test-Path $src2) {
    Copy-Item $src2 $dst2 -Force
    $f2 = Get-Item $dst2
    Write-Host ("  OK -> " + $dst2 + " (" + ([math]::Round($f2.Length/1KB)) + " KB, " + $f2.LastWriteTime.ToString('HH:mm:ss') + ")") -ForegroundColor Green
} else {
    Write-Host "  MISSING source $src2" -ForegroundColor Red
}

# ----- 3. Refresh stub SubModule.xml content with the new DefaultModule=true -----
# The stubs in the user's install were created during an earlier phase with
# DefaultModule=false. Push the new versions from crest/stubs/.
Write-Host ''
Write-Host '[3/4] Refresh stub SubModule.xml files (DefaultModule=true)' -ForegroundColor Cyan
foreach ($stub in @('Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen')) {
    $sSrc = Join-Path 'C:\dev\bannerlord\crest\stubs' ($stub + '\SubModule.xml')
    $sDst = Join-Path $gameRoot ('Modules\' + $stub + '\SubModule.xml')
    if (Test-Path $sSrc) {
        Copy-Item $sSrc $sDst -Force
        Write-Host ("  OK -> " + $stub) -ForegroundColor Green
    } else {
        Write-Host ("  MISSING source for " + $stub) -ForegroundColor Red
    }
}

# ----- 4. Run Crest-Doctor -Health to verify the new stub status output -----
Write-Host ''
Write-Host '[4/4] Crest-Doctor -Health (verify new stub status output)' -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\tools\doctor\Crest-Doctor.ps1' -Health
