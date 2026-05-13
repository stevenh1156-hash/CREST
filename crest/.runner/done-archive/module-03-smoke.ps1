$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force
Write-Host "==> Functions exported:" -ForegroundColor Green
Get-Command -Module Crest.Dev | ForEach-Object { Write-Host "    $($_.Name)" }

Write-Host ""
Write-Host "######## Get-CrestStatus ########" -ForegroundColor Cyan
Get-CrestStatus

Write-Host ""
Write-Host "######## Test-CrestNamespaces ########" -ForegroundColor Cyan
$auditOk = Test-CrestNamespaces

Write-Host ""
Write-Host "######## Build-CrestRepo Harmony ########" -ForegroundColor Cyan
$buildOk = Build-CrestRepo -Name Harmony

Write-Host ""
Write-Host "######## Commit-CrestRepo (no-op) ########" -ForegroundColor Cyan
$commitOk = Commit-CrestRepo -Name Harmony -Message "smoke test"

Write-Host ""
Write-Host ("==> Summary: audit={0} build={1} commit={2}" -f $auditOk, $buildOk, $commitOk) -ForegroundColor Green
exit 0
