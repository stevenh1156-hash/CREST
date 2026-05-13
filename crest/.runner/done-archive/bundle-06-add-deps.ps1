Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Re-assembling bundle with upstream third-party deps included..." -ForegroundColor Cyan
$ok = Build-CrestBundle -SkipBuild
if (-not $ok) { exit 1 }

Write-Host ""
$bin = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client'
$count = (Get-ChildItem $bin -Filter '*.dll' | Measure-Object).Count
Write-Host ("==> Bundle now has $count DLLs") -ForegroundColor Cyan

# Quick verify that the deps we expected are actually present
$mustHave = @(
    'Microsoft.Extensions.DependencyInjection.dll',
    'Microsoft.Extensions.DependencyInjection.Abstractions.dll',
    'Microsoft.Extensions.Logging.dll',
    'Microsoft.Extensions.Logging.Abstractions.dll',
    'Microsoft.Extensions.Options.dll',
    'Microsoft.Extensions.Primitives.dll',
    'Serilog.dll',
    'BUTR.CrashReport.dll',
    'System.Memory.dll',
    'System.Buffers.dll'
)
$missing = $mustHave | Where-Object { -not (Test-Path (Join-Path $bin $_)) }
if ($missing) {
    Write-Host "==> Still missing critical deps:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "    $_" }
    exit 1
} else {
    Write-Host "==> All critical third-party deps present." -ForegroundColor Green
}

Deploy-CrestToBannerlord | Out-Null
Write-Host ""
Write-Host "==> Redeployed. Try launching again." -ForegroundColor Green
exit 0
