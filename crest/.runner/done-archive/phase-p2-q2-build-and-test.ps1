# Phase P.2 + Q.2 build & test runner.
#
# 1. Compiles Crest.Harmony with the new CrestPatchSelfTest.cs (Phase P.2).
# 2. Hot-swaps Crest.Harmony.dll into the deployed CREST bundle.
# 3. Runs the synthetic-fixture test for Migrate-ModSourceToCrest.ps1
#    (Phase Q.2). Exits non-zero if either step fails.

Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> [1/2] Phase P.2: rebuilding Crest.Harmony with CrestPatchSelfTest..." -ForegroundColor Cyan
$ok = Build-CrestRepo -Name Harmony -Clean
if (-not $ok) { Write-Host "Phase P.2 build failed" -ForegroundColor Red; exit 1 }

$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
$src = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll'
if (Test-Path $src) {
    Copy-Item $src -Destination $bin -Force
    Write-Host "==> Hot-swapped Crest.Harmony.dll into deployed bundle" -ForegroundColor Green
} else {
    Write-Host "Build claimed success but Crest.Harmony.dll not at expected path: $src" -ForegroundColor Red
    exit 1
}

# Heal the deployed SubModule.xml. dotnet build's BUTRModule.Sdk auto-deploy
# step rewrites the deployed CREST/SubModule.xml from the source _Module
# template, with $moduleid$ substituted. The substitution previously
# produced bogus DLLName="CREST.dll" / SubModuleClassType="CREST.SubModule"
# entries that broke the game at launch. The source template now hardcodes
# the correct values, but on a clean rebuild the deployed copy is whatever
# the SDK wrote -- copy our known-good source over it just to be sure.
$xmlSrc = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\_Module\SubModule.xml'
$xmlDst = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\SubModule.xml'
if (Test-Path $xmlSrc) {
    [IO.File]::WriteAllText($xmlDst, [IO.File]::ReadAllText($xmlSrc))
    Write-Host "==> Healed deployed SubModule.xml from CREST source template" -ForegroundColor Green
}

# Clear runtime.log so the next launch's CrestPatchSelfTest output is identifiable
$logFile = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\runtime.log'
if (Test-Path $logFile) { Remove-Item $logFile -Force }

# Verbose patch-dump toggle was useful for the first diagnostic run; off by
# default now. Flip RuntimeSelfTestVerbose to true in
# Modules\CREST\crest.json manually if a future debugging session needs the
# 313-line patched-methods dump again.

Write-Host ""
Write-Host "==> [2/2] Phase Q.2: running source-mode migrator smoke test..." -ForegroundColor Cyan
$testScript = 'C:\dev\bannerlord\crest\tools\migrate\Test-MigrateModSource.ps1'
# Run as a child process so a parse error / unhandled exception in the test
# script reliably surfaces as a non-zero exit code -- previously dot-sourcing
# / direct invocation would skip $LASTEXITCODE assignment when the script
# died at parse time, and the runner would falsely declare "passed".
$global:LASTEXITCODE = 0
& powershell -NoProfile -ExecutionPolicy Bypass -File $testScript
$rc = $LASTEXITCODE
if ($rc -ne 0) {
    Write-Host "Phase Q.2 smoke test failed with exit code $rc" -ForegroundColor Red
    exit $rc
}

Write-Host ""
Write-Host "==> All Phase P.2 + Q.2 work passed." -ForegroundColor Green
Write-Host "    Launch the game to exercise CrestPatchSelfTest -- output will land in:" -ForegroundColor White
Write-Host "      $logFile" -ForegroundColor White
Write-Host "    Phase Q.2 source migrator is at:" -ForegroundColor White
Write-Host "      C:\dev\bannerlord\crest\tools\migrate\Migrate-ModSourceToCrest.ps1" -ForegroundColor White
exit 0
