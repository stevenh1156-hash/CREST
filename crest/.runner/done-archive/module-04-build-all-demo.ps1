# Demo: build everything through Crest.Dev. This is what most jobs look like now.
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Status before build:" -ForegroundColor Cyan
Get-CrestStatus

Write-Host ""
Write-Host "==> Audit:" -ForegroundColor Cyan
$auditOk = Test-CrestNamespaces

Write-Host ""
Write-Host "==> Building all four repos in dependency order..." -ForegroundColor Cyan
$buildOk = Build-AllCrestRepos

Write-Host ""
Write-Host "==> Final artifacts:" -ForegroundColor Cyan
Get-CrestArtifacts

Write-Host ""
Write-Host ("==> Demo: audit={0} build={1}" -f $auditOk, $buildOk) -ForegroundColor $(if ($auditOk -and $buildOk) {'Green'} else {'Red'})
exit 0
