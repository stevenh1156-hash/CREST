$ErrorActionPreference = 'Continue'

$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$launcher = Join-Path $gameRoot 'bin\Win64_Shipping_Client\TaleWorlds.MountAndBlade.Launcher.exe'
$logFile = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Mount and Blade II Bannerlord\Configs\ModLogs\crest-hide-stubs.log'

Write-Host '==> Build minimal HideCrestStubsPatch (no-op, just writes log)' -ForegroundColor Cyan
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

# Clear log
if (Test-Path $logFile) { Remove-Item $logFile -Force }

# Launch
Write-Host ''
Write-Host '==> Launching...' -ForegroundColor Cyan
$proc = Start-Process -FilePath $launcher -PassThru
Start-Sleep -Seconds 14
$proc.Refresh()
if ($proc.HasExited) {
    Write-Host ('   EXITED early code=' + $proc.ExitCode) -ForegroundColor Red
} else {
    Write-Host ('   running with ' + $proc.Modules.Count + ' modules') -ForegroundColor Green
    Stop-Process -Id $proc.Id -Force
}

Write-Host ''
Write-Host '==> Debug log:' -ForegroundColor Cyan
if (Test-Path $logFile) { Get-Content $logFile | ForEach-Object { Write-Host ('   ' + $_) } }
else { Write-Host '   (none)' -ForegroundColor Red }
