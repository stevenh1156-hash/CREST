$ErrorActionPreference = 'Continue'

$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'

Write-Host '==> Rebuild Bannerlord.BLSE.Shared (Release config; cascades into 5x LauncherEx + embeds)' -ForegroundColor Cyan
Push-Location $blseRoot
try {
    $output = & dotnet build src\Bannerlord.BLSE.Shared\Bannerlord.BLSE.Shared.csproj `
        --configuration Release `
        -p:GenerateDocumentationFile=false `
        -nowarn:CS1591 `
        --nologo `
        -v minimal 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "build FAILED" -ForegroundColor Red
        $output | Where-Object { $_ -match 'error|FAILED' } | Select-Object -First 25 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        exit 1
    }
    Write-Host '   build OK' -ForegroundColor Green
    $output | Where-Object { $_ -match 'GZipped|EmbeddedResources' } | Select-Object -First 8 | ForEach-Object { Write-Host ('   ' + $_) -ForegroundColor DarkGray }
} finally { Pop-Location }

# Deploy the freshly-built BLSE.Shared.dll to the user's bin
$srcDll = Get-ChildItem $blseRoot -Recurse -Filter 'Bannerlord.BLSE.Shared.dll' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\bin\\Release\\' -and $_.FullName -notmatch '\\obj\\' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $srcDll) { Write-Host 'NO BLSE.Shared.dll found' -ForegroundColor Red; exit 1 }

$dstDll = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.BLSE.Shared.dll'
Copy-Item $srcDll.FullName $dstDll -Force
Write-Host ''
Write-Host ("==> Deployed " + $srcDll.FullName) -ForegroundColor Green
Write-Host ('   to: ' + $dstDll)
Write-Host ('   size: ' + ([math]::Round((Get-Item $dstDll).Length/1KB)) + ' KB')
Write-Host ('   timestamp: ' + (Get-Item $dstDll).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))

# Clear log and launch test
$candidates = @(
    'C:\Temp\crest-hide-stubs.log',
    (Join-Path $env:TEMP 'crest-hide-stubs.log'),
    (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Mount and Blade II Bannerlord\Configs\ModLogs\crest-hide-stubs.log')
)
foreach ($p in $candidates) { if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue } }

Write-Host ''
Write-Host '==> Launch test' -ForegroundColor Cyan
$gameLauncher = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.BLSE.LauncherEx.exe'
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
