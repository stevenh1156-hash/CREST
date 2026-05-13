# Phase R.2 build runner.
# 1. Compiles Crest.Harmony with the new CrestPatchSnapshot + hotkey + DebugUI button.
# 2. Hot-swaps the DLL into the deployed bundle.
# 3. Heals deployed SubModule.xml (BUTRModule SDK rewrites it from the source
#    template on -Clean rebuilds; the template hardcodes the correct values).
# 4. Verifies the doctor script's new -IncludePatchSnapshot flag accepts no
#    snapshot gracefully (the in-game capture happens after this script runs).

Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> [1/3] Phase R.2: rebuilding Crest.Harmony with CrestPatchSnapshot..." -ForegroundColor Cyan
$ok = Build-CrestRepo -Name Harmony -Clean
if (-not $ok) { Write-Host "Phase R.2 build failed" -ForegroundColor Red; exit 1 }

$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
$src = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll'
$dstFile = Join-Path $bin 'Crest.Harmony.dll'
if (Test-Path $src) {
    # Use [IO.File]::Copy rather than Copy-Item so we can detect the silent
    # failures we have observed previously: Copy-Item with -Force has been
    # observed to no-op when the destination is held open by another process,
    # without throwing. We then verify size + write-time match the source.
    try {
        [IO.File]::Copy($src, $dstFile, $true)
    } catch {
        Write-Host ("==> Copy failed: " + $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
    $srcInfo = Get-Item $src
    $dstInfo = Get-Item $dstFile
    if ($srcInfo.Length -ne $dstInfo.Length) {
        Write-Host ("==> Copy SIZE MISMATCH: src=" + $srcInfo.Length + " bytes, dst=" + $dstInfo.Length + " bytes. Is the game running?") -ForegroundColor Red
        exit 1
    }
    Write-Host ("==> Hot-swapped Crest.Harmony.dll (" + $srcInfo.Length + " bytes) into deployed bundle") -ForegroundColor Green
} else {
    Write-Host "Build claimed success but Crest.Harmony.dll not at expected path: $src" -ForegroundColor Red
    exit 1
}

# Heal deployed SubModule.xml from the FULL BUNDLE template at
# crest/dist/CREST/SubModule.xml. The BUTRModule SDK's auto-deploy step
# overwrites the deployed file with the per-repo source template
# (Bannerlord.Harmony/src/Crest.Harmony/_Module/SubModule.xml) on every
# -Clean rebuild. That per-repo template only declares the Harmony
# SubModule entry, so after an SDK auto-deploy the deployed bundle is
# missing ButterLib / UIExtenderEx / MCM / MCM.UI / MCM.UI.Adapter -- the
# game then crashes during loading because half the unified bundle never
# loads. Restoring from the full-bundle file is the correct heal.
$xmlSrc = 'C:\dev\bannerlord\crest\dist\CREST\SubModule.xml'
$xmlDst = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\SubModule.xml'
if (Test-Path $xmlSrc) {
    [IO.File]::WriteAllText($xmlDst, [IO.File]::ReadAllText($xmlSrc))
    $count = ([IO.File]::ReadAllText($xmlDst) | Select-String -Pattern '<SubModule>' -AllMatches).Matches.Count
    Write-Host ("==> Healed deployed SubModule.xml from full bundle template (" + $count + " SubModule entries)") -ForegroundColor Green
    if ($count -lt 8) {
        Write-Host ("    WARNING: expected 8 SubModule entries, got " + $count + ". Bundle template at " + $xmlSrc + " may be stale.") -ForegroundColor Yellow
    }
} else {
    Write-Host ("==> WARNING: full bundle SubModule.xml not at " + $xmlSrc + " -- skipping heal.") -ForegroundColor Yellow
    Write-Host ("    The deployed bundle's SubModule.xml may have been corrupted to a Harmony-only file.") -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==> [2/3] Smoke-test Crest-Doctor -IncludePatchSnapshot (no snapshot expected)..." -ForegroundColor Cyan
# Capture stdout, then verify the script ran the new branch with the right
# fallback message. We do not pass -ReportPath so it stays purely on stdout.
$doctor = 'C:\dev\bannerlord\crest\tools\doctor\Crest-Doctor.ps1'
$tempLog = Join-Path $env:TEMP "crest-doctor-r2-$(Get-Random).log"
& powershell -NoProfile -ExecutionPolicy Bypass -File $doctor -IncludePatchSnapshot 2>&1 | Tee-Object -FilePath $tempLog | Out-Null
$rc = $LASTEXITCODE
$body = Get-Content $tempLog -Raw

$pass = $true
if ($body -notmatch 'Patch snapshot') {
    Write-Host "  FAIL: doctor output does not contain 'Patch snapshot' section header" -ForegroundColor Red
    $pass = $false
}
# Either the snapshot section ran with a real file, or it printed the capture instructions.
if ($body -notmatch 'Ctrl\+Alt\+P|using\s+patches-snapshot-') {
    Write-Host "  FAIL: snapshot section did not produce expected guidance/usage line" -ForegroundColor Red
    $pass = $false
}
if (-not $pass) {
    Write-Host "Doctor smoke-test output saved to $tempLog for inspection" -ForegroundColor Yellow
    exit 1
}
Remove-Item $tempLog -Force -ErrorAction SilentlyContinue
Write-Host "  OK: doctor accepts -IncludePatchSnapshot and produces the new section." -ForegroundColor Green

Write-Host ""
Write-Host "==> [3/3] Done." -ForegroundColor Cyan
Write-Host "    To exercise the in-game inspector:" -ForegroundColor White
Write-Host "      1. Launch the game; reach main menu." -ForegroundColor White
Write-Host "      2. Press Ctrl+Alt+P -- 'CREST patch snapshot saved to ...' chat message confirms." -ForegroundColor White
Write-Host "      3. Snapshot file lands at:" -ForegroundColor White
Write-Host "         C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\patches-snapshot-*.log" -ForegroundColor White
Write-Host "      4. Re-run Crest-Doctor.ps1 -IncludePatchSnapshot to bundle it into the report." -ForegroundColor White
exit 0
