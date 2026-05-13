$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host '==> Wipe runtime.log so we get fresh diagnostic on next launch' -ForegroundColor Cyan
$rl = 'C:\dev\bannerlord\crest\runtime.log'
if (Test-Path $rl) { Clear-Content $rl; Write-Host '  cleared' }

Write-Host ''
Write-Host '==> Rebuild Harmony with hardened CrestMessageStyle (logs binding result)' -ForegroundColor Cyan
$ok = Build-CrestRepo -Name 'Harmony'
if (-not $ok) { exit 1 }

Write-Host ''
Write-Host '==> Re-flip + regen shims' -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\shims\flip-internals-public.ps1'
& 'C:\dev\bannerlord\crest\shims\generate-shims.ps1'

Write-Host ''
Write-Host '==> Reassemble + redeploy' -ForegroundColor Cyan
$ok = Build-CrestFullBundle -Version '1.3.0' -SkipBuild
if (-not $ok) { exit 2 }
$ok = Deploy-CrestFullToBannerlord
if (-not $ok) { exit 3 }

Write-Host ''
Write-Host '==> Done. Launch via Steam, get to main menu, then exit. After exit:' -ForegroundColor Green
Write-Host '    runtime.log will have a [CrestMessageStyle] line saying which TW namespace bound.'
Write-Host '    Mod-load messages should be off-white if patch succeeded.'
