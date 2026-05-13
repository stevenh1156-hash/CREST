$ErrorActionPreference = 'Continue'

# Phase N: build-verify the two new files
#   1. Crest.Harmony with CrestEnsureStubs.cs
#   2. Bannerlord.LauncherEx with HideCrestStubsPatch.cs
#
# Pure compile check -- no deploy yet. Confirms the new code parses,
# binds correctly to BUTRLauncherModuleVM internals, and produces DLLs.

Write-Host '==> Phase N build verification' -ForegroundColor Cyan
Write-Host ''

# ----- 1. Crest.Harmony -----
Write-Host '[1/2] Building Crest.Harmony (with new CrestEnsureStubs.cs)' -ForegroundColor Cyan

Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force
$harmonyOk = Build-CrestRepo -Name Harmony -Loud
if ($harmonyOk) {
    Write-Host '   Crest.Harmony: OK' -ForegroundColor Green
} else {
    Write-Host '   Crest.Harmony: FAILED -- see errors above' -ForegroundColor Red
}

# ----- 2. Bannerlord.LauncherEx (BLSE fork) -----
Write-Host ''
Write-Host '[2/2] Building Bannerlord.LauncherEx (with new HideCrestStubsPatch.cs)' -ForegroundColor Cyan

$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameFolder = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
Push-Location $blseRoot
try {
    $args = @(
        'build', 'src/Bannerlord.LauncherEx/Bannerlord.LauncherEx.csproj',
        '--configuration', 'Release',
        "-p:GameFolder=$gameFolder",
        '-p:GameVersion=1.4.1',
        '-p:GenerateDocumentationFile=false',
        '-nowarn:CS1591',
        '--nologo',
        '-v', 'minimal'
    )
    $output = & dotnet @args 2>&1
    $exit = $LASTEXITCODE
    if ($exit -eq 0) {
        Write-Host '   LauncherEx: OK' -ForegroundColor Green
        $output | Where-Object { $_ -match 'Build succeeded|->' } | Select-Object -First 5 | ForEach-Object { Write-Host "                   $_" -ForegroundColor DarkGray }
    } else {
        Write-Host "   LauncherEx: FAILED (exit $exit)" -ForegroundColor Red
        $output | Where-Object { $_ -match 'error |Build FAILED|HideCrestStubsPatch' } | Select-Object -First 15 | ForEach-Object { Write-Host "                   $_" -ForegroundColor Red }
    }
} finally {
    Pop-Location
}

# ----- Verify the new DLLs -----
Write-Host ''
Write-Host '==> Built DLLs' -ForegroundColor Cyan
$harmonyDll = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll'
$blseDll = 'C:\dev\bannerlord\Bannerlord.BLSE\src\Bannerlord.LauncherEx\bin\Release\netstandard2.0\Bannerlord.LauncherEx.dll'
foreach ($p in @($harmonyDll, $blseDll)) {
    if (Test-Path $p) {
        $f = Get-Item $p
        Write-Host ("   " + $f.FullName + "  (" + ([math]::Round($f.Length / 1KB)) + " KB, " + $f.LastWriteTime.ToString('HH:mm:ss') + ")") -ForegroundColor Green
    } else {
        Write-Host ("   MISSING: " + $p) -ForegroundColor Red
    }
}
