$ErrorActionPreference = 'Continue'

$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$gameLauncher = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.BLSE.LauncherEx.exe'

Write-Host '==> Build all BLSE projects in dependency order (Release)' -ForegroundColor Cyan

$projects = @(
    'src\Bannerlord.BLSE.Shared\Bannerlord.BLSE.Shared.csproj',
    'src\Bannerlord.BLSE\Bannerlord.BLSE.csproj',
    'src\Bannerlord.LauncherEx\Bannerlord.LauncherEx.csproj',
    'src\Bannerlord.BLSE.Loaders.LauncherEx\Bannerlord.BLSE.Loaders.LauncherEx.csproj',
    'src\Bannerlord.BLSE.Loaders.AppDomainManager\Bannerlord.BLSE.Loaders.AppDomainManager.csproj'
)

Push-Location $blseRoot
try {
    foreach ($p in $projects) {
        $name = (Split-Path $p -Leaf) -replace '\.csproj$', ''
        Write-Host ('  building ' + $name) -ForegroundColor Cyan
        $args = @(
            'build', $p,
            '--configuration', 'Release',
            '-p:GameFolder=' + $gameRoot,
            '-p:GenerateDocumentationFile=false',
            '-nowarn:CS1591',
            '--nologo',
            '-v', 'quiet'
        )
        $output = & dotnet @args 2>&1
        if ($LASTEXITCODE -eq 0) {
            $output | Where-Object { $_ -match 'Build succeeded' } | Select-Object -First 1 | ForEach-Object { Write-Host ('    ' + $_) -ForegroundColor Green }
        } else {
            Write-Host ('    FAIL exit=' + $LASTEXITCODE) -ForegroundColor Red
            $output | Where-Object { $_ -match 'error |Build FAILED' } | Select-Object -First 6 | ForEach-Object { Write-Host ('      ' + $_) -ForegroundColor Red }
            exit 1
        }
    }
} finally { Pop-Location }

# Find newly built BLSE.LauncherEx.exe
$builtExe = Get-ChildItem $blseRoot -Recurse -Filter 'Bannerlord.BLSE.LauncherEx.exe' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\obj\\' -and $_.FullName -match '\\Release\\' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 3
Write-Host ''
Write-Host '==> Built EXE candidates (most-recent 3):' -ForegroundColor Cyan
foreach ($e in $builtExe) {
    Write-Host ('   ' + $e.LastWriteTime.ToString('HH:mm:ss') + '  ' + ([math]::Round($e.Length/1KB)) + 'KB  ' + $e.FullName)
}

# Pick the newest non-publish one (or publish if it's bigger)
$src = $builtExe | Where-Object { $_.FullName -notmatch '\\publish\\' } | Select-Object -First 1
if (-not $src) { $src = $builtExe | Select-Object -First 1 }
if (-not $src) { Write-Host 'no exe found' -ForegroundColor Red; exit 1 }

# Deploy
Copy-Item $src.FullName $gameLauncher -Force
# Also copy the .exe.config alongside
$srcCfg = $src.FullName + '.config'
if (Test-Path $srcCfg) { Copy-Item $srcCfg ($gameLauncher + '.config') -Force }
Write-Host ''
Write-Host ("==> Deployed " + $src.FullName + " -> " + $gameLauncher) -ForegroundColor Green
Write-Host ('    timestamp: ' + (Get-Item $gameLauncher).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))

# Clean log paths and launch
$candidates = @(
    'C:\Temp\crest-hide-stubs.log',
    (Join-Path $env:TEMP 'crest-hide-stubs.log'),
    (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Mount and Blade II Bannerlord\Configs\ModLogs\crest-hide-stubs.log')
)
foreach ($p in $candidates) { if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue } }

Write-Host ''
Write-Host '==> Launching freshly-built BLSE.LauncherEx.exe...' -ForegroundColor Cyan
$proc = Start-Process -FilePath $gameLauncher -PassThru
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
