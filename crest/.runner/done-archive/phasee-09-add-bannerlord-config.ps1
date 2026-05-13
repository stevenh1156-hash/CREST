$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host '==> Re-stage BLSE (now copies .exe.config files + emits Bannerlord.exe.config)' -ForegroundColor Cyan
$ok = Build-CrestBlse -StagingBlseBin 'C:\dev\bannerlord\crest\dist\full\bin\Win64_Shipping_Client' -SkipBuild
if (-not $ok) { exit 1 }

Write-Host ''
Write-Host '==> Deploy to game' -ForegroundColor Cyan
$ok = Deploy-CrestFullToBannerlord
if (-not $ok) { exit 2 }

Write-Host ''
Write-Host '==> Verify Bannerlord.exe.config now exists with AppDomainManager redirect' -ForegroundColor Cyan
$cfg = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\bin\Win64_Shipping_Client\Bannerlord.exe.config'
if (Test-Path $cfg) {
    $f = Get-Item $cfg
    Write-Host ('  ' + $f.LastWriteTime + '  ' + $f.Length + 'B  ' + $f.Name) -ForegroundColor Green
    Write-Host '  --- content ---'
    Get-Content $cfg | ForEach-Object { Write-Host ('    ' + $_) }
} else {
    Write-Host '  MISSING!' -ForegroundColor Red
}

Write-Host ''
Write-Host '==> Wipe stale BLSE_lasterror.log' -ForegroundColor Cyan
$err = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\bin\Win64_Shipping_Client\BLSE_lasterror.log'
if (Test-Path $err) {
    Remove-Item $err -Force
    Write-Host '  removed'
}

Write-Host ''
Write-Host '==> Repackage v1.3.0 zip' -ForegroundColor Cyan
$zip = New-CrestFullZip -Version '1.3.0'
if ($zip) { Write-Host ('  zip: ' + $zip) }

Write-Host ''
Write-Host '==> Done. Launch the game any way you like (Steam direct, BLSE.Launcher.exe, etc.)' -ForegroundColor Green
Write-Host '    BLSE will inject in all paths now. Then ALT+~, blse.version should work.'
