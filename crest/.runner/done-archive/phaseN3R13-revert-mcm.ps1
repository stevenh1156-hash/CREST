$ErrorActionPreference = 'Continue'

Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host '==> Rebuild MCM (filter reverted; just defensive build)' -ForegroundColor Cyan
$ok = Build-CrestRepo -Name MCM
if (-not $ok) { Write-Host 'build FAILED' -ForegroundColor Red; exit 1 }

# Deploy only the MCM-related outputs
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$installBin = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'

$mainOut = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src\Crest.MCM\bin\Release\netstandard2.0'
$uiOut = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI\bin\Stable_Release\netstandard2.0'

foreach ($f in 'Crest.MCM.dll','Crest.MCM.UI.Adapter.MCMv5.dll','MCMv5.dll','CREST.v1.4.1.dll','Bannerlord.ModuleLoader.CREST.dll') {
    foreach ($candidate in @((Join-Path $mainOut $f), (Join-Path $uiOut $f))) {
        if (Test-Path $candidate) {
            Copy-Item $candidate (Join-Path $installBin $f) -Force
            Write-Host ('   deployed ' + $f + ' from ' + (Split-Path $candidate -Parent)) -ForegroundColor Green
            break
        }
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
Write-Host '==> Now launch the game from Steam, click Play, see if it gets past the loading screen.' -ForegroundColor Yellow
