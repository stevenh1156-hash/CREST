$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$env:GameFolder = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'

Write-Host '==> Step 1: rebuild BLSE.Shared with the HarmonyFinder CREST-fallback patch' -ForegroundColor Cyan
Push-Location $blseRoot
try {
    foreach ($p in @(
        'src\Bannerlord.BLSE.Shared\Bannerlord.BLSE.Shared.csproj',
        'src\Bannerlord.BLSE\Bannerlord.BLSE.csproj',
        'src\Bannerlord.LauncherEx\Bannerlord.LauncherEx.csproj',
        'src\Bannerlord.BLSE.Loaders.Launcher\Bannerlord.BLSE.Loaders.Launcher.csproj',
        'src\Bannerlord.BLSE.Loaders.LauncherEx\Bannerlord.BLSE.Loaders.LauncherEx.csproj',
        'src\Bannerlord.BLSE.Loaders.Standalone\Bannerlord.BLSE.Loaders.Standalone.csproj',
        'src\Bannerlord.BLSE.Loaders.AppDomainManager\Bannerlord.BLSE.Loaders.AppDomainManager.csproj'
    )) {
        $name = (Split-Path $p -Leaf) -replace '\.csproj$', ''
        Write-Host ('  building ' + $name)
        $output = & dotnet build $p --configuration Release '-p:GenerateDocumentationFile=false' '-nowarn:CS1591' --nologo -v quiet 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host ('    FAIL ' + $name) -ForegroundColor Red
            $output | Where-Object { $_ -match '(error|Build FAILED)' } | Select-Object -First 6 | ForEach-Object { Write-Host ('      ' + $_) -ForegroundColor Red }
            exit 1
        }
    }
} finally { Pop-Location }
Write-Host '  all BLSE projects rebuilt' -ForegroundColor Green

Write-Host ''
Write-Host '==> Step 2: rebuild full CREST bundle (BLSE staged, stubs slimmed to xml only)' -ForegroundColor Cyan
$ok = Build-CrestFullBundle -Version '1.3.0' -SkipBuild
if (-not $ok) { exit 2 }

Write-Host ''
Write-Host '==> Step 3: wipe existing fat stub folders + redeploy slim stubs' -ForegroundColor Cyan
$gameModules = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules'
foreach ($s in @('Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen')) {
    $p = Join-Path $gameModules $s
    if (Test-Path $p) {
        Remove-Item -Recurse -Force $p
        Write-Host ('  wiped ' + $s)
    }
}
$ok = Deploy-CrestFullToBannerlord
if (-not $ok) { exit 3 }

Write-Host ''
Write-Host '==> Step 4: verify stub footprint (each should be ~1 KB SubModule.xml only)' -ForegroundColor Cyan
foreach ($s in @('Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen')) {
    $p = Join-Path $gameModules $s
    $files = Get-ChildItem -Recurse -File $p -ErrorAction SilentlyContinue
    $size = ($files | Measure-Object -Property Length -Sum).Sum
    Write-Host ('  ' + $s + ': ' + $files.Count + ' files, ' + $size + ' bytes total')
    foreach ($f in $files) {
        $rel = $f.FullName.Replace($p + '\', '')
        Write-Host ('    ' + $f.Length + 'B  ' + $rel)
    }
}

Write-Host ''
Write-Host '==> Step 5: wipe stale BLSE_lasterror.log + repackage' -ForegroundColor Cyan
$err = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\bin\Win64_Shipping_Client\BLSE_lasterror.log'
if (Test-Path $err) { Remove-Item $err -Force; Write-Host '  cleared lasterror' }

$zip = New-CrestFullZip -Version '1.3.0'
if ($zip) { Write-Host ('  zip: ' + $zip) -ForegroundColor Green }

Write-Host ''
Write-Host '==> Done. Launch via Steam — community mods should still load (engine sees stub Ids),' -ForegroundColor Green
Write-Host '    BLSE will find 0Harmony in CREST\bin via the new fallback probe,'
Write-Host '    and Modules\Bannerlord.X\ folders are now SubModule.xml only.'
