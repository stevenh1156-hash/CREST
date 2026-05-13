$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Bundle (SkipBuild - DLLs are already current)" -ForegroundColor Cyan
$ok = Build-CrestBundle -SkipBuild -Version '1.0.0'
if (-not $ok) { exit 1 }

Write-Host ""
Write-Host "==> Deploy" -ForegroundColor Cyan
$ok = Deploy-CrestToBannerlord
if (-not $ok) { exit 2 }

# Verify the deployed bundle has the shim DLLs
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
Write-Host ""
Write-Host "==> Verifying shim DLLs are in deployed bin:" -ForegroundColor Cyan
foreach ($n in 'Bannerlord.Harmony.dll','Bannerlord.ButterLib.dll','Bannerlord.UIExtenderEx.dll','MCMv5.dll') {
    $p = Join-Path $bin $n
    if (Test-Path $p) {
        $sz = (Get-Item $p).Length
        Write-Host ("    [OK] {0,9:N0}B  {1}" -f $sz, $n) -ForegroundColor Green
    } else {
        Write-Host ("    [MISS]            {0}" -f $n) -ForegroundColor Red
    }
}

# Verify SubModule.xml class FQNs
$xml = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\SubModule.xml'
Write-Host ""
Write-Host "==> SubModule.xml class FQNs:" -ForegroundColor Cyan
([xml](Get-Content $xml -Raw)).Module.SubModules.SubModule | ForEach-Object {
    Write-Host ("    {0,-40}  ({1})" -f $_.Name.value, $_.SubModuleClassType.value)
}

Write-Host ""
Write-Host "==> READY - launch the game" -ForegroundColor Green
Write-Host "    Expected: 6-entry config loads cleanly, mods compiled against upstream BUTR work via shims" -ForegroundColor DarkGray
