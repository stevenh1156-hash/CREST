$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Rebuilding MCM (with restored MCMUISubModule.ctor body, since this DLL still" -ForegroundColor Cyan
Write-Host "    ships in the bundle - just isn't referenced from SubModule.xml in v1.0)" -ForegroundColor Cyan
$ok = Build-CrestRepo -Name 'MCM'
if (-not $ok) { exit 1 }

Write-Host ""
Write-Host "==> Re-bundle (Build-CrestBundle now uses the new 6-entry template)" -ForegroundColor Cyan
$ok = Build-CrestBundle -SkipBuild -Version '1.0.0'
if (-not $ok) { exit 2 }

Write-Host ""
Write-Host "==> Deploy" -ForegroundColor Cyan
$ok = Deploy-CrestToBannerlord
if (-not $ok) { exit 3 }

# Verify the deployed SubModule.xml has 6 entries
$xmlPath = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\SubModule.xml'
$xml = [xml](Get-Content $xmlPath -Raw)
$count = ($xml.Module.SubModules.SubModule | Measure-Object).Count
Write-Host ""
Write-Host ("==> SubModule.xml has $count entries (expected 6)") -ForegroundColor $(if ($count -eq 6) { 'Green' } else { 'Red' })
$xml.Module.SubModules.SubModule | ForEach-Object {
    Write-Host ("    - {0}" -f $_.Name.value)
}

Write-Host ""
Write-Host "==> CREST v1.0 baseline ready - launch the game to confirm" -ForegroundColor Green
