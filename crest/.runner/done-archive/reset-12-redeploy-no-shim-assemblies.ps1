$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Re-bundle (shims excluded from <Assemblies> to avoid dependency conflict)" -ForegroundColor Cyan
$ok = Build-CrestBundle -SkipBuild -Version '1.0.0'
if (-not $ok) { exit 1 }

Write-Host ""
Write-Host "==> Deploy" -ForegroundColor Cyan
$ok = Deploy-CrestToBannerlord
if (-not $ok) { exit 2 }

# Verify SubModule.xml has no shim DLL references in Assemblies
$xml = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\SubModule.xml'
$x = [xml](Get-Content $xml -Raw)
Write-Host ""
Write-Host "==> SubModule.xml structure:" -ForegroundColor Cyan
foreach ($s in $x.Module.SubModules.SubModule) {
    Write-Host ("    {0,-40}  {1}::{2}" -f $s.Name.value, $s.DLLName.value, $s.SubModuleClassType.value)
    if ($s.Assemblies -and $s.Assemblies.Assembly) {
        $asms = @($s.Assemblies.Assembly | ForEach-Object { $_.value })
        # Flag any shim DLLs accidentally still listed
        $shimNames = @('Bannerlord.Harmony.dll','Bannerlord.ButterLib.dll','Bannerlord.UIExtenderEx.dll','MCMv5.dll')
        $listed = $asms | Where-Object { $shimNames -contains $_ }
        if ($listed) {
            Write-Host ("       SHIMS STILL LISTED: $($listed -join ', ')") -ForegroundColor Red
        }
    }
}

# Confirm shim DLLs are still in bin (just not pre-loaded via SubModule.xml)
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
Write-Host ""
Write-Host "==> Shim DLLs still in bin (for on-demand resolution):" -ForegroundColor Cyan
foreach ($n in 'Bannerlord.Harmony.dll','Bannerlord.ButterLib.dll','Bannerlord.UIExtenderEx.dll','MCMv5.dll') {
    $p = Join-Path $bin $n
    Write-Host ("    {0,-32} {1}" -f $n, $(if (Test-Path $p) { 'present' } else { 'MISSING' }))
}

Write-Host ""
Write-Host "==> READY - launch the game" -ForegroundColor Green
