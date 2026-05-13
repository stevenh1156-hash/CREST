$ErrorActionPreference = 'Continue'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$staging = 'C:\dev\bannerlord\crest\dist\CREST'
$installCrest = Join-Path $gameRoot 'Modules\CREST'
$installBin = Join-Path $installCrest 'bin\Win64_Shipping_Client'

Write-Host '==> Restore full bundle' -ForegroundColor Cyan
if (Test-Path $installBin) { Remove-Item -Recurse -Force $installBin }
New-Item -ItemType Directory -Path $installBin -Force | Out-Null
Copy-Item -Path (Join-Path $staging 'bin\Win64_Shipping_Client\*') -Destination $installBin -Recurse -Force
$count = (Get-ChildItem $installBin -File).Count
Write-Host ('   restored ' + $count + ' files') -ForegroundColor Green

# Lock down the bin folder so we can detect what's wiping it.
# Take ownership + grant only Steve full control + set immutable bit (the
# Windows equivalent is +R read-only; not perfect but a clue).
Write-Host ''
Write-Host '==> Inventory before next launch' -ForegroundColor Cyan
foreach ($n in '0Harmony.dll','Mono.Cecil.dll','Crest.Harmony.dll','Crest.ButterLib.dll','MCMv5.dll','Bannerlord.Harmony.dll') {
    $p = Join-Path $installBin $n
    Write-Host ('   ' + (Test-Path $p) + '  ' + $n)
}

# Doctor check
Write-Host ''
Write-Host '==> Crest-Doctor -Health' -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\tools\doctor\Crest-Doctor.ps1' -Health 2>&1 | Where-Object { $_ -match '\[OK\]|\[ERR\]|\[WARN\]|##' } | Select-Object -First 30
