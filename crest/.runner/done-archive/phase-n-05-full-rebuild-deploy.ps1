$ErrorActionPreference = 'Continue'

Write-Host '==> Phase N: full rebuild + deploy' -ForegroundColor Cyan

Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

# ----- 1. Build all four CREST forks -----
Write-Host ''
Write-Host '[1/5] Build all CREST forks' -ForegroundColor Cyan
$built = Build-AllCrestRepos
if (-not $built) {
    Write-Host '   FAILED' -ForegroundColor Red
    exit 1
}

# ----- 2. Build BLSE LauncherEx (Release_140 / GameVersion=1.4.0) -----
Write-Host ''
Write-Host '[2/5] Build Bannerlord.LauncherEx (BLSE)' -ForegroundColor Cyan
Push-Location 'C:\dev\bannerlord\Bannerlord.BLSE'
try {
    $args = @(
        'build', 'src/Bannerlord.LauncherEx/Bannerlord.LauncherEx.csproj',
        '--configuration', 'Release_140',
        "-p:GameFolder=C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord",
        '-p:GameVersion=1.4.0',
        '-p:GenerateDocumentationFile=false',
        '-nowarn:CS1591', '--nologo', '-v', 'minimal'
    )
    $output = & dotnet @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   FAILED exit=$LASTEXITCODE" -ForegroundColor Red
        $output | Select-Object -Last 10 | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        exit 1
    }
    Write-Host '   OK' -ForegroundColor Green
} finally { Pop-Location }

# ----- 3. Stage the bundle -----
Write-Host ''
Write-Host '[3/5] Stage CREST bundle (Build-CrestBundle -SkipBuild)' -ForegroundColor Cyan
$staged = Build-CrestBundle -SkipBuild
if (-not $staged) {
    Write-Host '   FAILED' -ForegroundColor Red
    exit 1
}

# ----- 4. Deploy: stage -> Modules\CREST + LauncherEx -> game bin -----
Write-Host ''
Write-Host '[4/5] Deploy to game install' -ForegroundColor Cyan
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$staging = 'C:\dev\bannerlord\crest\dist\CREST'

# CREST module: wipe target's bin\ + ModuleData\, copy fresh from staging.
# We don't wipe the whole CREST folder because crest.json + SubModule.xml + runtime.log
# live there too and are user-side state we don't want to clobber.
$installCrest = Join-Path $gameRoot 'Modules\CREST'
if (-not (Test-Path $installCrest)) { New-Item -ItemType Directory -Path $installCrest -Force | Out-Null }
$installBin = Join-Path $installCrest 'bin\Win64_Shipping_Client'
if (Test-Path $installBin) { Remove-Item -Recurse -Force $installBin }
New-Item -ItemType Directory -Path $installBin -Force | Out-Null

# Copy bin contents
Copy-Item -Path (Join-Path $staging 'bin\Win64_Shipping_Client\*') -Destination $installBin -Recurse -Force
$binCount = (Get-ChildItem $installBin -File).Count
Write-Host ("   CREST bin: " + $binCount + " files") -ForegroundColor Green

# Copy SubModule.xml (don't overwrite if user has local edits to crest.json)
Copy-Item -Path (Join-Path $staging 'SubModule.xml') -Destination $installCrest -Force
Copy-Item -Path (Join-Path $staging 'Unblock-CrestInstall.ps1') -Destination $installCrest -Force -ErrorAction SilentlyContinue
# BEW assets at module root
foreach ($asset in 'errorui.htm','config.json','solutions.json') {
    $src = Join-Path $staging $asset
    if (Test-Path $src) { Copy-Item $src -Destination $installCrest -Force }
}
# ModuleData
if (Test-Path (Join-Path $staging 'ModuleData')) {
    if (Test-Path (Join-Path $installCrest 'ModuleData')) { Remove-Item -Recurse -Force (Join-Path $installCrest 'ModuleData') }
    Copy-Item -Path (Join-Path $staging 'ModuleData') -Destination $installCrest -Recurse -Force
}

# LauncherEx into game bin
$blseSrc = 'C:\dev\bannerlord\Bannerlord.BLSE\src\Bannerlord.LauncherEx\bin\Release_140\netstandard2.0\Bannerlord.LauncherEx.dll'
$blseDst = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.LauncherEx.dll'
Copy-Item $blseSrc $blseDst -Force
Write-Host ("   LauncherEx: " + (Get-Item $blseDst).LastWriteTime.ToString('HH:mm:ss')) -ForegroundColor Green

# Refresh stub SubModule.xml files from canonical sources
foreach ($stub in @('Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen')) {
    $sSrc = Join-Path 'C:\dev\bannerlord\crest\stubs' ($stub + '\SubModule.xml')
    $sDst = Join-Path $gameRoot ('Modules\' + $stub + '\SubModule.xml')
    if (Test-Path $sSrc) {
        $stubDir = Split-Path $sDst -Parent
        if (-not (Test-Path $stubDir)) { New-Item -ItemType Directory -Path $stubDir -Force | Out-Null }
        Copy-Item $sSrc $sDst -Force
    }
}
Write-Host '   Stub SubModule.xml files refreshed' -ForegroundColor Green

# ----- 5. Crest-Doctor -Health to verify clean state -----
Write-Host ''
Write-Host '[5/5] Crest-Doctor -Health' -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\tools\doctor\Crest-Doctor.ps1' -Health
