$ErrorActionPreference = 'Continue'

Write-Host '==> Phase N.3: hide internal MCM settings from mod-options list' -ForegroundColor Cyan

Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

# Build only MCM (the change is in src-ui/Crest.MCM.UI)
Write-Host ''
Write-Host '==> Build MCM' -ForegroundColor Cyan
$ok = Build-CrestRepo -Name MCM
if (-not $ok) { Write-Host 'build FAILED' -ForegroundColor Red; exit 1 }

# Repackage + deploy bundle (skip rebuild since we just built)
Write-Host ''
Write-Host '==> Stage + deploy bundle' -ForegroundColor Cyan
$staged = Build-CrestBundle -SkipBuild
if (-not $staged) { Write-Host 'staging failed' -ForegroundColor Red; exit 1 }

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$staging = 'C:\dev\bannerlord\crest\dist\CREST'
$installBin = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'

# Copy only the MCM-related DLLs (don't disturb other deploys)
foreach ($name in @('Crest.MCM.dll','Crest.MCM.UI.Adapter.MCMv5.dll','MCMv5.dll')) {
    $src = Join-Path $staging "bin\Win64_Shipping_Client\$name"
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $installBin $name) -Force
        Write-Host ("   deployed " + $name) -ForegroundColor Green
    }
}

# Smoke test launcher
Write-Host ''
Write-Host '==> Launcher smoke test' -ForegroundColor Cyan
$bin = Join-Path $gameRoot 'bin\Win64_Shipping_Client'
$proc = Start-Process -FilePath (Join-Path $bin 'TaleWorlds.MountAndBlade.Launcher.exe') -WorkingDirectory $bin -PassThru
Start-Sleep -Seconds 14
if ($proc.HasExited) { Write-Host ('   EXITED ' + $proc.ExitCode) -ForegroundColor Red }
else { Write-Host ('   running ' + $proc.Modules.Count + ' modules') -ForegroundColor Green; Stop-Process -Id $proc.Id -Force }

Write-Host ''
Write-Host '==> Done. Launch the game, open Mod Options. Should see only CREST + any consumer mods, no ButterLib/MCM/MCM UI entries.' -ForegroundColor Yellow
