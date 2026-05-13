$ErrorActionPreference = 'Continue'

$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$gameLauncher = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.BLSE.LauncherEx.exe'
$logFile = 'C:\dev\bannerlord\hide-debug.log'

if (Test-Path $logFile) { Remove-Item $logFile -Force }

# Rebuild Shared which cascades through all 5 LauncherEx variants and re-embeds
Write-Host '==> Rebuild BLSE.Shared (cascades 5x LauncherEx + embeds)' -ForegroundColor Cyan
Push-Location $blseRoot
try {
    $output = & dotnet build src\Bannerlord.BLSE.Shared\Bannerlord.BLSE.Shared.csproj `
        --configuration Release -p:GenerateDocumentationFile=false -nowarn:CS1591 --nologo -v quiet 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "build FAILED" -ForegroundColor Red
        $output | Where-Object { $_ -match 'error|FAILED' } | Select-Object -First 25 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        exit 1
    }
    Write-Host '   OK' -ForegroundColor Green
} finally { Pop-Location }

# Deploy
$src = Get-ChildItem $blseRoot -Recurse -Filter 'Bannerlord.BLSE.Shared.dll' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\bin\\Release\\' -and $_.FullName -notmatch '\\obj\\' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
$dst = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.BLSE.Shared.dll'
Copy-Item $src.FullName $dst -Force

# Launch
Write-Host ''
Write-Host '==> Launching launcher...' -ForegroundColor Cyan
$proc = Start-Process -FilePath $gameLauncher -PassThru
Start-Sleep -Seconds 12
$proc.Refresh()
if ($proc.HasExited) { Write-Host ('   EXITED code=' + $proc.ExitCode) -ForegroundColor Red }
else { Write-Host ('   running ' + $proc.Modules.Count + ' modules') -ForegroundColor Green; Stop-Process -Id $proc.Id -Force }

Write-Host ''
Write-Host "==> Did C:\dev\bannerlord\hide-debug.log get written?" -ForegroundColor Cyan
if (Test-Path $logFile) {
    Get-Content $logFile | ForEach-Object { Write-Host ('   ' + $_) -ForegroundColor Green }
} else {
    Write-Host '   NO -- patch is NOT being called' -ForegroundColor Red
}
