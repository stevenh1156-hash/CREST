$ErrorActionPreference = 'Continue'

$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$launcher = Join-Path $gameRoot 'bin\Win64_Shipping_Client\TaleWorlds.MountAndBlade.Launcher.exe'

# Clear all candidate log paths
$candidates = @(
    'C:\Temp\crest-hide-stubs.log',
    'C:\dev\bannerlord\crest\crest-hide-stubs-launcher.log',
    (Join-Path $env:TEMP 'crest-hide-stubs.log'),
    (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Mount and Blade II Bannerlord\Configs\ModLogs\crest-hide-stubs.log')
)
foreach ($p in $candidates) {
    if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
}

Write-Host '==> Build minimal-multipath HideCrestStubsPatch' -ForegroundColor Cyan
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

# Launch
Write-Host ''
Write-Host '==> Launching launcher...' -ForegroundColor Cyan
$proc = Start-Process -FilePath $launcher -PassThru
Start-Sleep -Seconds 14
$proc.Refresh()
if ($proc.HasExited) {
    Write-Host ('   EXITED early code=' + $proc.ExitCode) -ForegroundColor Red
} else {
    Write-Host ('   running OK with ' + $proc.Modules.Count + ' modules') -ForegroundColor Green
    Stop-Process -Id $proc.Id -Force
}

Write-Host ''
Write-Host '==> Which candidate log paths got written?' -ForegroundColor Cyan
foreach ($p in $candidates) {
    if (Test-Path $p) {
        Write-Host ('   FOUND: ' + $p) -ForegroundColor Green
        Get-Content $p | ForEach-Object { Write-Host ('     ' + $_) }
    } else {
        Write-Host ('   none:  ' + $p) -ForegroundColor DarkGray
    }
}
