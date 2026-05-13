Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Phase P.2: rebuilding Crest.Harmony with new CrestPatchSelfTest..." -ForegroundColor Cyan
$ok = Build-CrestRepo -Name Harmony -Clean
if (-not $ok) { Write-Host "==> Build failed" -ForegroundColor Red; exit 1 }

# Hot-swap just the Crest.Harmony.dll into the deployed bundle so the user can
# launch the game and exercise the new self-test without having to rebuild
# the whole CREST bundle. The bundle's other DLLs are unchanged by Phase P.2.
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
$src = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll'
if (Test-Path $src) {
    Copy-Item $src -Destination $bin -Force
    Write-Host "==> Hot-swapped Crest.Harmony.dll into deployed bundle" -ForegroundColor Green
} else {
    Write-Host "==> Build claimed success but Crest.Harmony.dll not at expected path: $src" -ForegroundColor Red
    exit 1
}

# Also clear any stale runtime.log so we can identify exactly the new run's output
$logFile = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\runtime.log'
if (Test-Path $logFile) { Remove-Item $logFile -Force; Write-Host "==> Cleared previous runtime.log" }

Write-Host ""
Write-Host "==> Ready. Launch the game; the self-test will run at OnBeforeInitialModuleScreenSetAsRoot" -ForegroundColor White
Write-Host "    (immediately after Native modules initialize, alongside ValidateLoadOrder)." -ForegroundColor White
Write-Host "    Output goes to $logFile" -ForegroundColor White
exit 0
