$ErrorActionPreference = 'Continue'
$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$bin = Join-Path $gameRoot 'bin\Win64_Shipping_Client'
$gameLauncher = Join-Path $bin 'Bannerlord.BLSE.LauncherEx.exe'

Write-Host '==> Build + deploy: stubs are now REMOVED from Modules2 entirely' -ForegroundColor Cyan

Push-Location $blseRoot
try {
    $output = & dotnet build src\Bannerlord.BLSE.Shared\Bannerlord.BLSE.Shared.csproj `
        --configuration Release -p:GenerateDocumentationFile=false -nowarn:CS1591 --nologo -v quiet 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "build FAILED" -ForegroundColor Red
        $output | Where-Object { $_ -match 'error|FAILED' } | Select-Object -First 15 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        exit 1
    }
    Write-Host '   build OK' -ForegroundColor Green
} finally { Pop-Location }

# Stale on-disk LauncherEx.dll must be gone
$staleDll = Join-Path $bin 'Bannerlord.LauncherEx.dll'
if (Test-Path $staleDll) { Remove-Item $staleDll -Force }

$src = Get-ChildItem $blseRoot -Recurse -Filter 'Bannerlord.BLSE.Shared.dll' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\bin\\Release\\' -and $_.FullName -notmatch '\\obj\\' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
Copy-Item $src.FullName (Join-Path $bin 'Bannerlord.BLSE.Shared.dll') -Force
Write-Host ('   deployed at ' + (Get-ItemPropertyValue (Join-Path $bin 'Bannerlord.BLSE.Shared.dll') LastWriteTime).ToString('HH:mm:ss')) -ForegroundColor Green

Write-Host ''
Write-Host '==> Smoke test' -ForegroundColor Cyan
$proc = Start-Process -FilePath $gameLauncher -WorkingDirectory $bin -PassThru
Start-Sleep -Seconds 14
$proc.Refresh()
if ($proc.HasExited) { Write-Host ('   EXITED code=' + $proc.ExitCode) -ForegroundColor Red }
else { Write-Host ('   running ' + $proc.Modules.Count + ' modules') -ForegroundColor Green; Stop-Process -Id $proc.Id -Force }

Write-Host ''
Write-Host '==> Open the launcher manually to verify stubs are now gone from the mod list.' -ForegroundColor Yellow
