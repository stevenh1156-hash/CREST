Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Pre-deploy state of Modules\:" -ForegroundColor Cyan
$modulesDir = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules'
Write-Host "    Modules at: $modulesDir"
Get-ChildItem $modulesDir -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in 'CREST','Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen' } |
    ForEach-Object { Write-Host "    found: $($_.Name)" }

Write-Host ""
Write-Host "==> Deploying bundle to Modules\CREST\..." -ForegroundColor Cyan
$ok = Deploy-CrestToBannerlord
if (-not $ok) {
    Write-Host "==> Deploy failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "==> Post-deploy verification:" -ForegroundColor Cyan
$crestDir = Join-Path $modulesDir 'CREST'
if (Test-Path $crestDir) {
    Write-Host "    CREST folder exists at $crestDir"
    $sub = Join-Path $crestDir 'SubModule.xml'
    if (Test-Path $sub) {
        Write-Host "    SubModule.xml present ($((Get-Item $sub).Length) bytes)"
    }
    $bin = Join-Path $crestDir 'bin\Win64_Shipping_Client'
    if (Test-Path $bin) {
        $dllCount = (Get-ChildItem $bin -Filter '*.dll' | Measure-Object).Count
        Write-Host "    bin\Win64_Shipping_Client has $dllCount DLLs"
    }
} else {
    Write-Host "    CREST folder NOT FOUND post-deploy" -ForegroundColor Red
    exit 1
}

# Double-check: are there any conflicting BUTR mod folders that might compete with CREST?
Write-Host ""
Write-Host "==> Conflict check (legacy BUTR mod folders that should be DISABLED):" -ForegroundColor Cyan
$conflicts = Get-ChildItem $modulesDir -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in 'Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen' }
if ($conflicts) {
    Write-Host "    Legacy BUTR mods present:"
    $conflicts | ForEach-Object { Write-Host "      $($_.Name)" -ForegroundColor Yellow }
    Write-Host "    NOTE: leave these UNTICKED in the launcher when testing CREST."
    Write-Host "          Or rename them to .disabled if you want them out of the way."
} else {
    Write-Host "    No legacy BUTR mods present." -ForegroundColor Green
}

Write-Host ""
Write-Host "==> READY FOR LAUNCH" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps (manual):"
Write-Host "  1. Launch Bannerlord."
Write-Host "  2. In the launcher, you should see ONE new entry: 'CREST'."
Write-Host "  3. Make sure these are TICKED:"
Write-Host "       Native, SandBoxCore, Sandbox, StoryMode, CustomBattle, CREST"
Write-Host "     UNTICK any legacy Bannerlord.Harmony/ButterLib/UIExtenderEx/MBOptionScreen"
Write-Host "     (otherwise they'll conflict)."
Write-Host "  4. Start a Singleplayer campaign (Sandbox is fine)."
Write-Host "  5. Once in the main menu (before clicking Singleplayer), you should see"
Write-Host "     'Mod Options' as one of the buttons. That's MCM working through CREST."
Write-Host "  6. Click Mod Options. The CREST settings UI should open. Should be empty"
Write-Host "     since no other mod has registered settings, but the screen itself opening"
Write-Host "     proves the whole stack (Harmony patches, UIExtenderEx, ButterLib DI, MCM)"
Write-Host "     is working end-to-end."
Write-Host ""
Write-Host "If anything fails, the most useful files to check are:"
Write-Host "  C:\Users\Steve\Documents\Mount and Blade II Bannerlord\logs\"
Write-Host "  (look for the latest 'rgl_log_xxx.txt' file)"
exit 0
