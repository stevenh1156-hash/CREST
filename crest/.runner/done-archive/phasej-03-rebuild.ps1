$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Phase J retry: patch VideoPlaybackState.OnVideoStarted instead" -ForegroundColor Cyan
$ok = Build-CrestRepo -Name 'Harmony'
if (-not $ok) { exit 1 }

Write-Host ""
Write-Host "==> Bundle + deploy" -ForegroundColor Cyan
$ok = Build-CrestBundle -SkipBuild -Version '1.0.0'
if (-not $ok) { exit 2 }
$ok = Deploy-CrestToBannerlord
if (-not $ok) { exit 3 }

Write-Host ""
Write-Host "==> READY - launch the game" -ForegroundColor Green
Write-Host "    Now patches VideoPlaybackState.OnVideoStarted to immediately fire OnVideoFinished."
Write-Host "    The state machine should advance to MBInitialState (main menu) the moment the engine"
Write-Host "    reports the video player is ready, before any frames are actually rendered."
