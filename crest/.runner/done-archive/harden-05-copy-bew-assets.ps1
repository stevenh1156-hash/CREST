$ErrorActionPreference = 'Continue'

$crestDir = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'
$bewSrc = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\BetterExceptionWindow'

if (-not (Test-Path $bewSrc)) {
    Write-Host "BEW source folder not found: $bewSrc" -ForegroundColor Red
    exit 1
}

Write-Host "==> Copying BEW root assets..."
foreach ($asset in 'errorui.htm','config.json','solutions.json') {
    $src = Join-Path $bewSrc $asset
    $dst = Join-Path $crestDir $asset
    if (Test-Path $src) {
        Copy-Item $src -Destination $dst -Force
        Write-Host "    copied $asset"
    } else {
        Write-Host "    missing source: $asset" -ForegroundColor Yellow
    }
}

Write-Host "==> Copying BEW ModuleData..."
$bewModData = Join-Path $bewSrc 'ModuleData'
if (Test-Path $bewModData) {
    $destModData = Join-Path $crestDir 'ModuleData'
    if (-not (Test-Path $destModData)) {
        New-Item -ItemType Directory -Path $destModData -Force | Out-Null
    }
    Copy-Item -Recurse -Path (Join-Path $bewModData '*') -Destination $destModData -Force
    Write-Host "    copied $((Get-ChildItem $destModData -Recurse -File | Measure-Object).Count) ModuleData files"
} else {
    Write-Host "    no ModuleData folder in BEW source"
}

Write-Host ""
Write-Host "==> Final deployment layout:"
Get-ChildItem $crestDir -File | ForEach-Object { Write-Host "    $($_.Name)" }
$bin = Join-Path $crestDir 'bin\Win64_Shipping_Client'
Write-Host "  bin\:"
Get-ChildItem $bin -File | ForEach-Object { Write-Host "    bin\$($_.Name)" }
$md = Join-Path $crestDir 'ModuleData'
if (Test-Path $md) {
    Write-Host "  ModuleData\:"
    Get-ChildItem $md -Recurse -File | ForEach-Object { Write-Host "    ModuleData\$($_.FullName.Replace($md + '\','').Replace('\','/'))" }
}

Write-Host ""
Write-Host "==> READY. Try launching with CREST + Native ticked." -ForegroundColor Green
exit 0
