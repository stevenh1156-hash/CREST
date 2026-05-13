$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

# Rebuild only Crest.Harmony - it's the only fork that knows the config filename
Write-Host "==> Rebuild Crest.Harmony (config filename now crest.json)" -ForegroundColor Cyan
$ok = Build-CrestRepo -Name 'Harmony'
if (-not $ok) { exit 1 }

Write-Host ""
Write-Host "==> Bundle + deploy" -ForegroundColor Cyan
$ok = Build-CrestBundle -SkipBuild -Version '1.0.0'
if (-not $ok) { exit 2 }
$ok = Deploy-CrestToBannerlord
if (-not $ok) { exit 3 }

# Show what's in Modules\CREST\
$crest = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'
Write-Host ""
Write-Host "==> Files in Modules\CREST\ (excluding bin\)" -ForegroundColor Cyan
Get-ChildItem $crest -File | Sort-Object Name | ForEach-Object {
    Write-Host ("    {0,9:N0}B  {1}" -f $_.Length, $_.Name)
}

Write-Host ""
Write-Host "==> READY - launch the game. Phase L Stage 1:" -ForegroundColor Green
Write-Host "    First launch CREATES Modules\CREST\crest.json with all sub-modules enabled."
Write-Host "    Edit crest.json + relaunch to disable specific sub-modules."
Write-Host "    Filename: 'crest.json' (avoids collision with BEW's 'config.json')"
