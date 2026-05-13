$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Phase L Stage 1: rebuild Harmony + ButterLib + MCM" -ForegroundColor Cyan
foreach ($name in 'Harmony','ButterLib','MCM') {
    Write-Host ""
    Write-Host "---- $name ----" -ForegroundColor DarkCyan
    if (-not (Build-CrestRepo -Name $name)) {
        Write-Error "$name build failed"
        exit 1
    }
}

Write-Host ""
Write-Host "==> Bundle + deploy" -ForegroundColor Cyan
$ok = Build-CrestBundle -SkipBuild -Version '1.0.0'
if (-not $ok) { exit 2 }
$ok = Deploy-CrestToBannerlord
if (-not $ok) { exit 3 }

# Show deployed config.json (will be auto-created on first launch by CrestConfig)
$config = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\config.json'
Write-Host ""
Write-Host "==> config.json status:" -ForegroundColor Cyan
if (Test-Path $config) {
    Write-Host "    EXISTS - first launch will read it"
    Get-Content $config | ForEach-Object { Write-Host "    $_" }
} else {
    Write-Host "    NOT YET CREATED - first launch with CREST will auto-write the default file"
}

Write-Host ""
Write-Host "==> READY - launch the game" -ForegroundColor Green
Write-Host "    First launch: CREST will write Modules\CREST\config.json with all flags = true"
Write-Host "    To disable a sub-module, edit the JSON and relaunch"
