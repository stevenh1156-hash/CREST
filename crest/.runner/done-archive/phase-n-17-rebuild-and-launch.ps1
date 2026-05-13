$ErrorActionPreference = 'Continue'

$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$launcher = Join-Path $gameRoot 'bin\Win64_Shipping_Client\TaleWorlds.MountAndBlade.Launcher.exe'
$logFile = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Mount and Blade II Bannerlord\Configs\ModLogs\crest-hide-stubs.log'

# Build
Write-Host '==> Build BLSE LauncherEx (no MixinCtorPostfix; top-level try/catch)' -ForegroundColor Cyan
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
Write-Host ('   deployed ' + (Get-Item $dst).LastWriteTime.ToString('HH:mm:ss')) -ForegroundColor Green

# Clear debug log
if (Test-Path $logFile) { Remove-Item $logFile -Force }

# Launch
Write-Host ''
Write-Host '==> Launching launcher...' -ForegroundColor Cyan
$proc = Start-Process -FilePath $launcher -PassThru
Start-Sleep -Seconds 12
$proc.Refresh()
if (-not $proc.HasExited) {
    Write-Host ('   running, ' + $proc.Modules.Count + ' modules loaded') -ForegroundColor Green
} else {
    Write-Host ('   EXITED early code=' + $proc.ExitCode) -ForegroundColor Red
}

# Read log
Write-Host ''
Write-Host '==> Debug log:' -ForegroundColor Cyan
if (Test-Path $logFile) {
    Get-Content $logFile | ForEach-Object { Write-Host ('   ' + $_) }
} else {
    Write-Host '   (still no log)' -ForegroundColor Red
}

# Kill launcher
if (-not $proc.HasExited) {
    Stop-Process -Id $proc.Id -Force
    Write-Host ''
    Write-Host '   killed launcher' -ForegroundColor DarkGray
}
