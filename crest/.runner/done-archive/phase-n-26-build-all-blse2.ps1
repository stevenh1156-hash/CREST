$ErrorActionPreference = 'Continue'

$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$gameLauncher = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.BLSE.LauncherEx.exe'

Write-Host '==> Build BLSE projects (Release config) in dependency order' -ForegroundColor Cyan

$projects = @(
    'src\Bannerlord.BLSE.Shared\Bannerlord.BLSE.Shared.csproj',
    'src\Bannerlord.BLSE\Bannerlord.BLSE.csproj',
    'src\Bannerlord.LauncherEx\Bannerlord.LauncherEx.csproj',
    'src\Bannerlord.BLSE.Loaders.LauncherEx\Bannerlord.BLSE.Loaders.LauncherEx.csproj'
)

Push-Location $blseRoot
try {
    foreach ($p in $projects) {
        $name = (Split-Path $p -Leaf) -replace '\.csproj$', ''
        Write-Host ('  building ' + $name) -ForegroundColor Cyan
        # Pass GameFolder via env var to dodge whitespace splitting issues
        $env:GameFolder = $gameRoot
        $output = & dotnet build $p --configuration Release -p:GenerateDocumentationFile=false -nowarn:CS1591 --nologo -v quiet 2>&1
        if ($LASTEXITCODE -eq 0) {
            $output | Where-Object { $_ -match 'Build succeeded' } | Select-Object -First 1 | ForEach-Object { Write-Host ('    ' + $_) -ForegroundColor Green }
        } else {
            Write-Host ('    FAIL exit=' + $LASTEXITCODE) -ForegroundColor Red
            $output | Where-Object { $_ -match 'error|Build FAILED' } | Select-Object -First 8 | ForEach-Object { Write-Host ('      ' + $_) -ForegroundColor Red }
            exit 1
        }
    }
} finally { Pop-Location }

# Find the most-recently-built EXE
Write-Host ''
Write-Host '==> Searching for built Bannerlord.BLSE.LauncherEx.exe' -ForegroundColor Cyan
$builtExes = Get-ChildItem $blseRoot -Recurse -Filter 'Bannerlord.BLSE.LauncherEx.exe' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\obj\\' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 5
foreach ($e in $builtExes) {
    Write-Host ('   ' + $e.LastWriteTime.ToString('HH:mm:ss') + '  ' + ([math]::Round($e.Length/1KB)) + 'KB  ' + $e.FullName.Substring($blseRoot.Length))
}

# Pick newest non-publish
$src = $builtExes | Where-Object { $_.FullName -notmatch '\\publish\\' } | Select-Object -First 1
if (-not $src) { $src = $builtExes | Select-Object -First 1 }
if (-not $src) { Write-Host '   NO EXE FOUND' -ForegroundColor Red; exit 1 }

Copy-Item $src.FullName $gameLauncher -Force
$srcCfg = $src.FullName + '.config'
if (Test-Path $srcCfg) { Copy-Item $srcCfg ($gameLauncher + '.config') -Force }
Write-Host ''
Write-Host ("   deployed " + (Split-Path $src.FullName -Leaf) + " -> " + $gameLauncher) -ForegroundColor Green
Write-Host ('   timestamp: ' + (Get-Item $gameLauncher).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))

# Clear log paths and launch test
$candidates = @(
    'C:\Temp\crest-hide-stubs.log',
    (Join-Path $env:TEMP 'crest-hide-stubs.log'),
    (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Mount and Blade II Bannerlord\Configs\ModLogs\crest-hide-stubs.log')
)
foreach ($p in $candidates) { if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue } }

Write-Host ''
Write-Host '==> Launch test' -ForegroundColor Cyan
$proc = Start-Process -FilePath $gameLauncher -PassThru
Start-Sleep -Seconds 14
$proc.Refresh()
if ($proc.HasExited) {
    Write-Host ('   EXITED code=' + $proc.ExitCode) -ForegroundColor Red
} else {
    Write-Host ('   running ' + $proc.Modules.Count + ' modules') -ForegroundColor Green
    Stop-Process -Id $proc.Id -Force
}

Write-Host ''
foreach ($p in $candidates) {
    if (Test-Path $p) {
        Write-Host ('   FOUND ' + $p) -ForegroundColor Green
        Get-Content $p | ForEach-Object { Write-Host ('     ' + $_) }
    }
}
