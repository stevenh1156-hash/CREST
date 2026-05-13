Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Building CREST bundle..." -ForegroundColor Cyan
$built = Build-CrestBundle -SkipBuild  # use already-fresh DLLs
if (-not $built) {
    Write-Host "==> bundle assembly failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "==> Verifying bundle layout..." -ForegroundColor Cyan
$staging = 'C:\dev\bannerlord\crest\dist\CREST'
$expected = @(
    'SubModule.xml',
    'bin\Win64_Shipping_Client\Crest.Harmony.dll',
    'bin\Win64_Shipping_Client\0Harmony.dll',
    'bin\Win64_Shipping_Client\Crest.ButterLib.dll',
    'bin\Win64_Shipping_Client\Crest.ButterLib.Implementation.dll',
    'bin\Win64_Shipping_Client\Crest.UIExtenderEx.dll',
    'bin\Win64_Shipping_Client\Crest.MCM.dll',
    'bin\Win64_Shipping_Client\Crest.MCM.UI.Adapter.MCMv5.dll',
    'bin\Win64_Shipping_Client\CREST.v1.4.1.dll',
    'bin\Win64_Shipping_Client\Bannerlord.ModuleLoader.CREST.dll'
)
$missing = 0
foreach ($e in $expected) {
    $p = Join-Path $staging $e
    if (Test-Path $p) {
        Write-Host ("    OK   {0}" -f $e) -ForegroundColor Green
    } else {
        Write-Host ("    MISS {0}" -f $e) -ForegroundColor Red
        $missing++
    }
}

Write-Host ""
Write-Host ("==> Bundle: {0} expected files, {1} missing" -f $expected.Count, $missing)
exit $(if ($missing -eq 0) {0} else {1})
