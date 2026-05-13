# Rebuild Crest.MCM.UI with the new try/catch wrappers + CrestEnabled gate,
# then redeploy CREST.v1.4.1.dll into the live module bin.
$ErrorActionPreference = 'Stop'

Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Build MCM repo (UI is the part we changed)" -ForegroundColor Cyan
$ok = Build-CrestRepo -Name 'MCM' -Loud:$false
if (-not $ok) {
    Write-Host "==> MCM build FAILED" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "==> Locate fresh CREST.v1.4.1.dll" -ForegroundColor Cyan
$builtDll = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI\bin\Stable_Release\netstandard2.0\CREST.v1.4.1.dll'
if (-not (Test-Path $builtDll)) {
    Write-Host "  MISSING: $builtDll" -ForegroundColor Red
    exit 2
}
$built = Get-Item $builtDll
Write-Host ("  built: {0}  ({1} bytes, {2})" -f $built.Name, $built.Length, $built.LastWriteTime)

Write-Host ""
Write-Host "==> Copy into live CREST module bin" -ForegroundColor Cyan
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
$dst = Join-Path $bin 'CREST.v1.4.1.dll'
Copy-Item -Path $builtDll -Destination $dst -Force

# Also copy the adapter if it rebuilt
$builtAdapter = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI\bin\Stable_Release\netstandard2.0\Crest.MCM.UI.Adapter.MCMv5.dll'
if (Test-Path $builtAdapter) {
    Copy-Item -Path $builtAdapter -Destination (Join-Path $bin 'Crest.MCM.UI.Adapter.MCMv5.dll') -Force
    Write-Host "  copied Crest.MCM.UI.Adapter.MCMv5.dll"
}

$deployed = Get-Item $dst
Write-Host ("  deployed: {0}  ({1} bytes, {2})" -f $deployed.Name, $deployed.Length, $deployed.LastWriteTime) -ForegroundColor Green

Write-Host ""
Write-Host "==> Done. Launch the game. If MCM UI still misbehaves, set"
Write-Host '    Modules\CREST\crest.json to {"MCMUI": false} to disable just'
Write-Host "    that piece without disabling the rest of CREST." -ForegroundColor Cyan
