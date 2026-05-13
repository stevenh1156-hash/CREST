$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Phase J: rebuild Crest.Harmony with intro-video skip patch" -ForegroundColor Cyan
$ok = Build-CrestRepo -Name 'Harmony'
if (-not $ok) { exit 1 }

Write-Host ""
Write-Host "==> Re-bundle + deploy" -ForegroundColor Cyan
$ok = Build-CrestBundle -SkipBuild -Version '1.0.0'
if (-not $ok) { exit 2 }
$ok = Deploy-CrestToBannerlord
if (-not $ok) { exit 3 }

Write-Host ""
Write-Host "==> Phase J ready" -ForegroundColor Green
Write-Host "    Patches TaleWorlds.Engine.VideoPlayerView.PlayVideo to skip videos with"
Write-Host "    'TWLogo' or 'Partners' in the path (only TWLogo_and_Partners.ivf matches)."
Write-Host "    Main-menu background loops + in-game cinematics are unaffected."
Write-Host "    Env opt-out: set CREST_SKIP_INTRO=0"
Write-Host ""
Write-Host "    Launch the game and you should go straight from launcher splash to main menu."
