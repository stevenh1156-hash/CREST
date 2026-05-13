$ErrorActionPreference = 'Continue'

$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$gameLauncher = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.BLSE.LauncherEx.exe'

# Clear logs
foreach ($f in @('C:\dev\bannerlord\manager-enable.log','C:\dev\bannerlord\hide-debug.log')) {
    if (Test-Path $f) { Remove-Item $f -Force }
}

# Rebuild Shared (which cascades into 5x LauncherEx + embeds)
Write-Host '==> Rebuild BLSE.Shared with traces in Manager.Enable' -ForegroundColor Cyan
Push-Location $blseRoot
try {
    $output = & dotnet build src\Bannerlord.BLSE.Shared\Bannerlord.BLSE.Shared.csproj `
        --configuration Release -p:GenerateDocumentationFile=false -nowarn:CS1591 --nologo -v quiet 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Host "build FAILED"; exit 1 }
    Write-Host '   OK' -ForegroundColor Green
} finally { Pop-Location }

# Deploy Shared
$src = Get-ChildItem $blseRoot -Recurse -Filter 'Bannerlord.BLSE.Shared.dll' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\bin\\Release\\' -and $_.FullName -notmatch '\\obj\\' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$dst = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.BLSE.Shared.dll'
Copy-Item $src.FullName $dst -Force

# Launch
Write-Host '==> Launching launcher' -ForegroundColor Cyan
$proc = Start-Process -FilePath $gameLauncher -PassThru
Start-Sleep -Seconds 12
$proc.Refresh()
if ($proc.HasExited) { Write-Host ('   EXITED code=' + $proc.ExitCode) -ForegroundColor Red }
else { Write-Host ('   running ' + $proc.Modules.Count + ' modules') -ForegroundColor Green; Stop-Process -Id $proc.Id -Force }

Write-Host ''
Write-Host '==> manager-enable.log:' -ForegroundColor Cyan
if (Test-Path 'C:\dev\bannerlord\manager-enable.log') {
    Get-Content 'C:\dev\bannerlord\manager-enable.log' | ForEach-Object { Write-Host ('   ' + $_) }
} else {
    Write-Host '   not written -- Manager.Enable() never ran!' -ForegroundColor Red
}

Write-Host ''
Write-Host '==> hide-debug.log:' -ForegroundColor Cyan
if (Test-Path 'C:\dev\bannerlord\hide-debug.log') {
    Get-Content 'C:\dev\bannerlord\hide-debug.log' | ForEach-Object { Write-Host ('   ' + $_) }
} else {
    Write-Host '   not written' -ForegroundColor Red
}
