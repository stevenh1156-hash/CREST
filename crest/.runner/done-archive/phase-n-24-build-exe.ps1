$ErrorActionPreference = 'Continue'

$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$launcher = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.BLSE.LauncherEx.exe'

Write-Host '==> Build Bannerlord.BLSE.Loaders.LauncherEx (the EXE)' -ForegroundColor Cyan
Push-Location $blseRoot
try {
    $args = @(
        'build', 'src/Bannerlord.BLSE.Loaders.LauncherEx/Bannerlord.BLSE.Loaders.LauncherEx.csproj',
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

# Find the built exe
$builtExe = Get-ChildItem $blseRoot -Recurse -Filter 'Bannerlord.BLSE.LauncherEx.exe' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match 'Release_140' -and $_.FullName -notmatch 'publish' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($builtExe) {
    Write-Host ("   built: " + $builtExe.FullName + " (" + ([math]::Round($builtExe.Length/1KB)) + "KB, " + $builtExe.LastWriteTime.ToString('HH:mm:ss') + ")") -ForegroundColor Green
} else {
    Write-Host '   ERROR: built exe not found' -ForegroundColor Red
    exit 1
}

# Deploy
Copy-Item $builtExe.FullName $launcher -Force
Write-Host ("   deployed " + (Get-Item $launcher).LastWriteTime.ToString('HH:mm:ss')) -ForegroundColor Green

# Clear log paths and launch
$candidates = @(
    'C:\Temp\crest-hide-stubs.log',
    'C:\dev\bannerlord\crest\crest-hide-stubs-launcher.log',
    (Join-Path $env:TEMP 'crest-hide-stubs.log'),
    (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Mount and Blade II Bannerlord\Configs\ModLogs\crest-hide-stubs.log')
)
foreach ($p in $candidates) { if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue } }

Write-Host ''
Write-Host '==> Launch Bannerlord.BLSE.LauncherEx.exe' -ForegroundColor Cyan
$proc = Start-Process -FilePath $launcher -PassThru
Start-Sleep -Seconds 14
$proc.Refresh()
if ($proc.HasExited) {
    Write-Host ('   EXITED code=' + $proc.ExitCode) -ForegroundColor Red
} else {
    Write-Host ('   running with ' + $proc.Modules.Count + ' modules') -ForegroundColor Green
    Stop-Process -Id $proc.Id -Force
}

Write-Host ''
Write-Host '==> Logs?' -ForegroundColor Cyan
foreach ($p in $candidates) {
    if (Test-Path $p) {
        Write-Host ('   FOUND ' + $p) -ForegroundColor Green
        Get-Content $p | ForEach-Object { Write-Host ('     ' + $_) }
    }
}
