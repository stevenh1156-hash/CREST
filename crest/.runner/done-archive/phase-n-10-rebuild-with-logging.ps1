$ErrorActionPreference = 'Continue'

Write-Host '==> Rebuild + redeploy + clear old log' -ForegroundColor Cyan

$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$logFile = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Mount and Blade II Bannerlord\Configs\ModLogs\crest-hide-stubs.log'

# Clear old debug log
if (Test-Path $logFile) { Remove-Item $logFile -Force }
Write-Host "   cleared $logFile" -ForegroundColor DarkGray

# Build
Push-Location $blseRoot
try {
    $args = @(
        'build', 'src/Bannerlord.LauncherEx/Bannerlord.LauncherEx.csproj',
        '--configuration', 'Release_140',
        "-p:GameFolder=$gameRoot",
        '-p:GameVersion=1.4.0',
        '-p:GenerateDocumentationFile=false',
        '-nowarn:CS1591', '--nologo', '-v', 'minimal'
    )
    $output = & dotnet @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "build FAILED" -ForegroundColor Red
        $output | Where-Object { $_ -match 'error|FAILED' } | Select-Object -First 25 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        exit 1
    }
    Write-Host '   build OK' -ForegroundColor Green
} finally { Pop-Location }

# Deploy
$src = Join-Path $blseRoot 'src\Bannerlord.LauncherEx\bin\Release_140\netstandard2.0\Bannerlord.LauncherEx.dll'
$dst = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.LauncherEx.dll'
Copy-Item $src $dst -Force
Write-Host ("   deployed " + (Get-Item $dst).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor Green

Write-Host ''
Write-Host '==> NEXT: launch the launcher (don''t click Play, just open it),' -ForegroundColor Yellow
Write-Host '    then close the launcher and run phase-n-11-read-log.ps1' -ForegroundColor Yellow
