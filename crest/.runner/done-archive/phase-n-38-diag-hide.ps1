$ErrorActionPreference = 'Continue'
$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$bin = Join-Path $gameRoot 'bin\Win64_Shipping_Client'
$gameLauncher = Join-Path $bin 'Bannerlord.BLSE.LauncherEx.exe'
$logFile = 'C:\dev\bannerlord\hide-debug.log'

if (Test-Path $logFile) { Remove-Item $logFile -Force }

Push-Location $blseRoot
try {
    $null = & dotnet build src\Bannerlord.BLSE.Shared\Bannerlord.BLSE.Shared.csproj `
        --configuration Release -p:GenerateDocumentationFile=false -nowarn:CS1591 --nologo -v quiet 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Host "FAILED build"; exit 1 }
} finally { Pop-Location }

# Stale on-disk DLL must not be there
$staleDll = Join-Path $bin 'Bannerlord.LauncherEx.dll'
if (Test-Path $staleDll) { Remove-Item $staleDll -Force }

$src = Get-ChildItem $blseRoot -Recurse -Filter 'Bannerlord.BLSE.Shared.dll' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\bin\\Release\\' -and $_.FullName -notmatch '\\obj\\' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
Copy-Item $src.FullName (Join-Path $bin 'Bannerlord.BLSE.Shared.dll') -Force

$proc = Start-Process -FilePath $gameLauncher -WorkingDirectory $bin -PassThru
Start-Sleep -Seconds 14
if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }

Write-Host '==> hide-debug.log:'
if (Test-Path $logFile) {
    Get-Content $logFile | ForEach-Object { Write-Host ('   ' + $_) }
} else { Write-Host '   (none)' -ForegroundColor Red }
