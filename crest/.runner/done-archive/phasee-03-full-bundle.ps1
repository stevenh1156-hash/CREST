$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host '==> Build-CrestFullBundle (skip CREST forks rebuild, BLSE is already built)' -ForegroundColor Cyan
$ok = Build-CrestFullBundle -Version '1.3.0' -SkipBuild
if (-not $ok) { Write-Host 'FAIL: bundle' -ForegroundColor Red; exit 1 }

Write-Host ''
Write-Host '==> Deploy to game' -ForegroundColor Cyan
$ok = Deploy-CrestFullToBannerlord
if (-not $ok) { Write-Host 'FAIL: deploy' -ForegroundColor Red; exit 2 }

Write-Host ''
Write-Host '==> Verify BLSE files in game bin' -ForegroundColor Cyan
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\bin\Win64_Shipping_Client'
$wanted = @('Bannerlord.BLSE.Launcher.exe','Bannerlord.BLSE.LauncherEx.exe','Bannerlord.BLSE.Standalone.exe',
            'Bannerlord.BLSE.dll','Bannerlord.BLSE.Shared.dll','Bannerlord.LauncherEx.dll',
            'Bannerlord.BLSE.AppDomainManager.dll')
foreach ($n in $wanted) {
    $p = Join-Path $bin $n
    if (Test-Path $p) {
        $f = Get-Item $p
        Write-Host ('  OK   ' + $n + ' (' + [math]::Round($f.Length/1KB) + ' KB)') -ForegroundColor Green
    } else {
        Write-Host ('  MISS ' + $n) -ForegroundColor Red
    }
}

Write-Host ''
Write-Host '==> Build CREST-v1.3.0.zip' -ForegroundColor Cyan
$zip = New-CrestFullZip -Version '1.3.0'
if ($zip) { Write-Host ('  zip: ' + $zip) -ForegroundColor Green }

Write-Host ''
Write-Host '==> Done. Two ways to launch:' -ForegroundColor Cyan
Write-Host '    Default game launcher (no BLSE init)        -> normal CREST experience'
Write-Host '    Bannerlord.BLSE.Launcher.exe                 -> CREST + BLSE early-init hooks'
Write-Host '    Bannerlord.BLSE.LauncherEx.exe               -> CREST + BLSE + BUTRLoader UI'
