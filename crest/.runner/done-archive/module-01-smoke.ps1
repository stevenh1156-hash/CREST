# Module smoke test: import Crest.Dev and exercise every exported function.
$ErrorActionPreference = 'Continue'

Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force
Write-Host "==> Module imported." -ForegroundColor Green
Write-Host "==> Exported functions:"
Get-Command -Module Crest.Dev | ForEach-Object { Write-Host "    $($_.Name)" }

Write-Host ""
Write-Host "######## Get-CrestRepo Harmony ########" -ForegroundColor Cyan
$h = Get-CrestRepo -Name Harmony
$h | Format-List | Out-String | Write-Host

Write-Host ""
Write-Host "######## Get-CrestStatus ########" -ForegroundColor Cyan
Get-CrestStatus

Write-Host ""
Write-Host "######## Audit-CrestNamespaces ########" -ForegroundColor Cyan
$auditClean = Audit-CrestNamespaces
Write-Host "  audit returned: $auditClean"

Write-Host ""
Write-Host "######## Build-CrestRepo Harmony ########" -ForegroundColor Cyan
$buildOk = Build-CrestRepo -Name Harmony
Write-Host "  build returned: $buildOk"

Write-Host ""
Write-Host "######## Get-CrestArtifacts ########" -ForegroundColor Cyan
Get-CrestArtifacts

Write-Host ""
Write-Host "######## Commit-CrestRepo (no-op test) ########" -ForegroundColor Cyan
$commitOk = Commit-CrestRepo -Name Harmony -Message "smoke-test (should not commit since tree is clean)"
Write-Host "  commit returned: $commitOk"

Write-Host ""
Write-Host "==> Smoke test done." -ForegroundColor Green
exit 0
