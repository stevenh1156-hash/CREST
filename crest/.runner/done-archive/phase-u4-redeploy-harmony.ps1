# Quick rebuild + redeploy of Crest.Harmony only — pulls in the new
# IsOnMainMenu probe (Phase O fix for v1.4.2 main-menu suppression).
$ErrorActionPreference = 'Stop'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Rebuilding Crest.Harmony" -ForegroundColor Cyan
$ok = Build-CrestRepo -Name Harmony -Clean
if (-not $ok) { Write-Host "build failed" -ForegroundColor Red; exit 1 }

$src = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll'
$dst = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client\Crest.Harmony.dll'
[IO.File]::Copy($src, $dst, $true)

$srcInfo = Get-Item $src
$dstInfo = Get-Item $dst
if ($srcInfo.Length -ne $dstInfo.Length) {
    Write-Host "Copy size mismatch -- is the game running?" -ForegroundColor Red
    exit 1
}
Write-Host ("==> Hot-swapped Crest.Harmony.dll (" + $srcInfo.Length + " bytes)") -ForegroundColor Green

# Also overlay into the dist bundle so future fresh-installs include the fix
$distDst = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client\Crest.Harmony.dll'
[IO.File]::Copy($src, $distDst, $true)
Write-Host "==> Updated dist bundle copy too" -ForegroundColor Green

exit 0
