$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host '==> Confirm BEW is back at expected path' -ForegroundColor Cyan
$bewSrc = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\BetterExceptionWindow'
if (Test-Path $bewSrc) {
    $files = Get-ChildItem -Recurse -File $bewSrc -ErrorAction SilentlyContinue
    Write-Host ('  found: ' + $files.Count + ' files at ' + $bewSrc) -ForegroundColor Green
} else {
    Write-Host ('  NOT FOUND at ' + $bewSrc) -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host '==> Rebuild full bundle (BEW will get picked up by Layer 6)' -ForegroundColor Cyan
$ok = Build-CrestFullBundle -Version '1.3.0' -SkipBuild
if (-not $ok) { exit 2 }

Write-Host ''
Write-Host '==> Redeploy' -ForegroundColor Cyan
$ok = Deploy-CrestFullToBannerlord
if (-not $ok) { exit 3 }

Write-Host ''
Write-Host '==> Verify BEW assets back in deployed CREST module' -ForegroundColor Cyan
$crest = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'
foreach ($n in @('errorui.htm','config.json','solutions.json','bin\Win64_Shipping_Client\BetterExceptionWindow.dll','bin\Win64_Shipping_Client\BetterExceptionWindowConfigUI.dll','bin\Win64_Shipping_Client\DotNetZip.dll')) {
    $p = Join-Path $crest $n
    if (Test-Path $p) {
        $f = Get-Item $p
        Write-Host ('  OK   ' + [math]::Round($f.Length/1KB) + 'KB  ' + $n) -ForegroundColor Green
    } else {
        Write-Host ('  MISS ' + $n) -ForegroundColor Red
    }
}

Write-Host ''
Write-Host '==> Verify slim stubs intact' -ForegroundColor Cyan
foreach ($s in @('Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen')) {
    $p = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\' + $s
    $files = Get-ChildItem -Recurse -File $p -ErrorAction SilentlyContinue
    $size = ($files | Measure-Object -Property Length -Sum).Sum
    Write-Host ('  ' + $s + ': ' + $files.Count + ' files, ' + $size + ' bytes')
}

Write-Host ''
Write-Host '==> Repackage zip' -ForegroundColor Cyan
$zip = New-CrestFullZip -Version '1.3.0'
if ($zip) { Write-Host ('  zip: ' + $zip) -ForegroundColor Green }

Write-Host ''
Write-Host '==> Done. Launch via Steam, expect: BEW back, stubs slim, BLSE active.' -ForegroundColor Green
