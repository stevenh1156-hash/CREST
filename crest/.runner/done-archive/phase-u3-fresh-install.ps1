# Phase U.3 — clean-uninstall + fresh-install smoke test.
#
# Walks the install state through:
#   1. Backup user's crest.json + capture state of LauncherData.xml
#   2. Delete deployed Modules/CREST + stubs (Modules/Bannerlord.{Harmony,
#      ButterLib, UIExtenderEx, MBOptionScreen})
#   3. Stage a fresh Modules/CREST from crest/dist/CREST/ (the bundle)
#   4. Restore the original crest.json on top so user toggles aren't lost
#   5. Verify with Crest-Doctor -Health
#
# Stubs are intentionally NOT recreated here — the in-game CrestEnsureStubs
# self-heals them on first launch, which is exactly the scenario this test
# exercises. If they fail to materialize, that's a real bug we want to see.

$ErrorActionPreference = 'Stop'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$crestSrc = 'C:\dev\bannerlord\crest\dist\CREST'
$crestDst = Join-Path $gameRoot 'Modules\CREST'
$stubIds  = @('Bannerlord.Harmony', 'Bannerlord.ButterLib', 'Bannerlord.UIExtenderEx', 'Bannerlord.MBOptionScreen')
$backupCfg = Join-Path $env:TEMP "crest-json-backup-$(Get-Date -Format yyyyMMdd-HHmmss).json"

# --- [1/5] Backup user's crest.json ---
Write-Host "==> [1/5] Backing up user's crest.json" -ForegroundColor Cyan
$srcCfg = Join-Path $crestDst 'crest.json'
if (Test-Path $srcCfg) {
    Copy-Item $srcCfg $backupCfg -Force
    Write-Host ("    saved -> " + $backupCfg) -ForegroundColor Green
} else {
    Write-Host "    no existing crest.json (fresh-install starting from nothing)" -ForegroundColor Yellow
}

# --- [2/5] Delete deployed CREST + stubs ---
Write-Host ""
Write-Host "==> [2/5] Deleting deployed CREST module + stubs" -ForegroundColor Cyan
foreach ($d in @($crestDst) + ($stubIds | ForEach-Object { Join-Path $gameRoot ('Modules\' + $_) })) {
    if (Test-Path $d) {
        try {
            Remove-Item -Recurse -Force $d
            Write-Host ("    deleted " + $d) -ForegroundColor Green
        } catch {
            Write-Host ("    FAILED to delete " + $d + ": " + $_.Exception.Message) -ForegroundColor Red
            Write-Host "    Is the game running? Close it and rerun." -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Host ("    not present, skipping " + $d) -ForegroundColor DarkGray
    }
}

# --- [3/5] Stage fresh Modules/CREST from dist ---
Write-Host ""
Write-Host "==> [3/5] Staging fresh Modules/CREST from $crestSrc" -ForegroundColor Cyan
if (-not (Test-Path $crestSrc)) {
    Write-Host ("    FAIL: $crestSrc not found. Build the bundle first.") -ForegroundColor Red
    exit 1
}
Copy-Item -Recurse -Force $crestSrc $crestDst
$copiedCount = (Get-ChildItem -Recurse -File $crestDst | Measure-Object).Count
Write-Host ("    copied " + $copiedCount + " files") -ForegroundColor Green

# --- [4/5] Restore original crest.json (preserve user's toggles) ---
Write-Host ""
Write-Host "==> [4/5] Restoring user's crest.json on top of fresh install" -ForegroundColor Cyan
if (Test-Path $backupCfg) {
    [IO.File]::Copy($backupCfg, $srcCfg, $true)
    Write-Host ("    restored from " + $backupCfg) -ForegroundColor Green
} else {
    Write-Host "    no backup -- fresh crest.json will be auto-created on first launch with all-true defaults" -ForegroundColor Yellow
}

# --- [5/5] Health check ---
Write-Host ""
Write-Host "==> [5/5] Running Crest-Doctor -Health to verify the fresh install" -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\dev\bannerlord\crest\tools\doctor\Crest-Doctor.ps1' -Health 2>&1 |
    Select-String -Pattern '(\[OK\]|\[ERR\]|\[WARN\]|\[INFO\]|^##)' |
    ForEach-Object { Write-Host $_ }

Write-Host ""
Write-Host "==> Fresh install complete." -ForegroundColor Green
Write-Host "    Stubs (Modules/Bannerlord.*) were intentionally left missing -- CrestEnsureStubs" -ForegroundColor White
Write-Host "    will self-heal them on first launch, exercising the auto-heal path." -ForegroundColor White
Write-Host "    Launch the game now: BUTR launcher should appear, you should reach main menu," -ForegroundColor White
Write-Host "    and a fresh runtime.log should show 'recreated 4 stub folder(s)'." -ForegroundColor White
exit 0
