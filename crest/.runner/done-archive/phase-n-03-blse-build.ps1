$ErrorActionPreference = 'Continue'

# Phase N: BLSE LauncherEx build with GameVersion=1.4.0 (compiles to v140 define
# which the source's #elif v134 || v140 branch expects). Game v1.4.1 still uses
# this BLSE build because BLSE's compile-time dispatch is on major.minor only.

Write-Host '==> BLSE LauncherEx build (Release_140 / v140 define)' -ForegroundColor Cyan

$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameFolder = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'

Push-Location $blseRoot
try {
    $args = @(
        'build', 'src/Bannerlord.LauncherEx/Bannerlord.LauncherEx.csproj',
        '--configuration', 'Release_140',
        "-p:GameFolder=$gameFolder",
        '-p:GameVersion=1.4.0',
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
        $output | Where-Object { $_ -match 'Build succeeded|->|Bannerlord\.LauncherEx\.dll' } | Select-Object -Last 5 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    } else {
        Write-Host "FAILED exit=$exit" -ForegroundColor Red
        $output | Where-Object { $_ -match 'error|FAILED|HideCrestStubs' } | Select-Object -First 25 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
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
