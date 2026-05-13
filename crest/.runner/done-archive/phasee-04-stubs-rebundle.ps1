$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host '==> Rebuild full bundle with stub-bin enrichment' -ForegroundColor Cyan
$ok = Build-CrestFullBundle -Version '1.3.0' -SkipBuild
if (-not $ok) { exit 1 }

Write-Host ''
Write-Host '==> Deploy' -ForegroundColor Cyan
$ok = Deploy-CrestFullToBannerlord
if (-not $ok) { exit 2 }

Write-Host ''
Write-Host '==> Verify Bannerlord.Harmony stub now has bin\ + DLLs' -ForegroundColor Cyan
$stubBin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\Bannerlord.Harmony\bin\Win64_Shipping_Client'
if (Test-Path $stubBin) {
    Get-ChildItem $stubBin | ForEach-Object {
        Write-Host ('  ' + [math]::Round($_.Length/1KB) + 'KB  ' + $_.Name) -ForegroundColor Green
    }
} else {
    Write-Host '  MISSING' -ForegroundColor Red
}

Write-Host ''
Write-Host '==> Verify Bannerlord.Harmony stub SubModule.xml version' -ForegroundColor Cyan
$sm = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\Bannerlord.Harmony\SubModule.xml'
[xml]$x = Get-Content $sm
Write-Host ('  Id      : ' + $x.Module.Id.value)
Write-Host ('  Version : ' + $x.Module.Version.value)

Write-Host ''
Write-Host '==> Repackage zip' -ForegroundColor Cyan
$zip = New-CrestFullZip -Version '1.3.0'

Write-Host ''
Write-Host '==> Done. Try Bannerlord.BLSE.LauncherEx.exe again.' -ForegroundColor Green
