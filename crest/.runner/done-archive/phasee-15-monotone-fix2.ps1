$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host '==> Wipe runtime.log' -ForegroundColor Cyan
$rl = 'C:\dev\bannerlord\crest\runtime.log'
if (Test-Path $rl) { Clear-Content $rl }

Write-Host ''
Write-Host '==> Rebuild Harmony with parameter rename fix' -ForegroundColor Cyan
$ok = Build-CrestRepo -Name 'Harmony'
if (-not $ok) { exit 1 }

& 'C:\dev\bannerlord\crest\shims\flip-internals-public.ps1'
& 'C:\dev\bannerlord\crest\shims\generate-shims.ps1'

Write-Host ''
Write-Host '==> Reassemble + redeploy' -ForegroundColor Cyan
$ok = Build-CrestFullBundle -Version '1.3.0' -SkipBuild
if (-not $ok) { exit 2 }
$ok = Deploy-CrestFullToBannerlord
if (-not $ok) { exit 3 }

Write-Host ''
Write-Host '==> Done. Launch + check colors. Expected runtime.log line:' -ForegroundColor Green
Write-Host '    [CrestMessageStyle] patched TaleWorlds.Library.InformationManager.DisplayMessage(InformationMessage)'
