$ErrorActionPreference = 'Continue'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$installBin = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'

# Bannerlord.ModuleLoader.CREST.dll is intentionally NOT in the bundle (per
# Build-CrestBundle comment): SubModule.xml points directly at CREST.v1.4.1.dll
# so the BUTR loader stub is bypassed. Having both DLLs loaded causes
# duplicate class-load conflicts -> game crashes on startup.
$loaderDll = Join-Path $installBin 'Bannerlord.ModuleLoader.CREST.dll'
$loaderPdb = Join-Path $installBin 'Bannerlord.ModuleLoader.CREST.pdb'
foreach ($p in @($loaderDll, $loaderPdb)) {
    if (Test-Path $p) {
        Remove-Item $p -Force
        Write-Host ('   removed ' + $p) -ForegroundColor Green
    }
}

$count = (Get-ChildItem $installBin -File).Count
Write-Host ''
Write-Host ('==> CREST/bin file count: ' + $count + ' (expected 49)') -ForegroundColor Cyan

# Also scan SubModule.xml to confirm it points at CREST.v1.4.1.dll, not the loader
$smXml = Join-Path $gameRoot 'Modules\CREST\SubModule.xml'
$content = Get-Content $smXml -Raw
$pointsAtLoader = $content -match 'Bannerlord\.ModuleLoader\.CREST'
$pointsAtVer = $content -match 'CREST\.v1\.4\.1'
Write-Host ('   SubModule.xml points at CREST.v1.4.1: ' + $pointsAtVer)
Write-Host ('   SubModule.xml points at ModuleLoader: ' + $pointsAtLoader)

Write-Host ''
Write-Host '==> Now relaunch via Steam.' -ForegroundColor Yellow
