$ErrorActionPreference = 'Continue'

# Phase N: re-attempt BLSE LauncherEx build with version-tagged configuration.
# The csproj has #error guards that require a Release_<version> configuration
# (Release_140 for game v1.4.1).

Write-Host '==> BLSE LauncherEx build (Release_140)' -ForegroundColor Cyan

$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameFolder = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'

Push-Location $blseRoot
try {
    $args = @(
        'build', 'src/Bannerlord.LauncherEx/Bannerlord.LauncherEx.csproj',
        '--configuration', 'Release_140',
        "-p:GameFolder=$gameFolder",
        '-p:GameVersion=1.4.1',
        '-p:GenerateDocumentationFile=false',
        '-nowarn:CS1591',
        '--nologo',
        '-v', 'minimal'
    )
    $output = & dotnet @args 2>&1
    $exit = $LASTEXITCODE
    Write-Host ''
    if ($exit -eq 0) {
        Write-Host "OK exit=$exit" -ForegroundColor Green
        $output | Select-Object -Last 8 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    } else {
        Write-Host "FAILED exit=$exit" -ForegroundColor Red
        $output | Where-Object { $_ -match 'error|HideCrestStubsPatch|FAILED' } | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    }

    Write-Host ''
    Write-Host '==> Built DLL' -ForegroundColor Cyan
    $dll = Join-Path $blseRoot 'src\Bannerlord.LauncherEx\bin\Release_140\netstandard2.0\Bannerlord.LauncherEx.dll'
    if (Test-Path $dll) {
        $f = Get-Item $dll
        Write-Host ("  " + $f.FullName) -ForegroundColor Green
        Write-Host ("  size:    " + ([math]::Round($f.Length / 1KB)) + " KB") -ForegroundColor Green
        Write-Host ("  written: " + $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor Green
    } else {
        Write-Host "  MISSING" -ForegroundColor Red
    }
} finally {
    Pop-Location
}
