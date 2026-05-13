$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host '==> Restoring our locally-built BLSE (overwrites Nexus reinstall)' -ForegroundColor Cyan
$ok = Deploy-CrestFullToBannerlord
if (-not $ok) { exit 1 }

Write-Host ''
Write-Host '==> Confirm BLSE files are now from our build (mtime should be today, post-22:00)' -ForegroundColor Cyan
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\bin\Win64_Shipping_Client'
foreach ($n in @('Bannerlord.BLSE.dll','Bannerlord.BLSE.Shared.dll','Bannerlord.LauncherEx.dll','Bannerlord.BLSE.Launcher.exe','Bannerlord.BLSE.LauncherEx.exe','Bannerlord.BLSE.AppDomainManager.dll')) {
    $p = Join-Path $bin $n
    if (Test-Path $p) {
        $f = Get-Item $p
        Write-Host ('  ' + $f.LastWriteTime + '  ' + [math]::Round($f.Length/1KB) + 'KB  ' + $n)
    }
}

Write-Host ''
Write-Host '==> Wipe the stale BLSE_lasterror.log so next run leaves a fresh trace' -ForegroundColor Cyan
$err = Join-Path $bin 'BLSE_lasterror.log'
if (Test-Path $err) {
    Remove-Item $err -Force
    Write-Host '  removed'
}

Write-Host ''
Write-Host '==> Done.'
Write-Host '  Use Bannerlord.BLSE.Launcher.exe (NOT LauncherEx — its UI has a known issue with this game version).'
Write-Host '  For dev console / blse.version, edit'
Write-Host '    Documents\Mount and Blade II Bannerlord\engine_config.txt'
Write-Host '  add a line: cheat_mode = 1'
