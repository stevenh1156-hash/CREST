$ErrorActionPreference = 'Continue'
$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$bin = Join-Path $gameRoot 'bin\Win64_Shipping_Client'
$gameLauncher = Join-Path $bin 'Bannerlord.BLSE.LauncherEx.exe'

foreach ($f in @('C:\dev\bannerlord\program-main.log','C:\dev\bannerlord\launcherex-launch.log','C:\dev\bannerlord\manager-enable.log','C:\dev\bannerlord\hide-debug.log')) {
    if (Test-Path $f) { Remove-Item $f -Force }
}

# Rebuild Shared
Write-Host '==> Rebuild Shared with traces in Program.Main and LauncherEx.Launch' -ForegroundColor Cyan
Push-Location $blseRoot
try {
    $output = & dotnet build src\Bannerlord.BLSE.Shared\Bannerlord.BLSE.Shared.csproj `
        --configuration Release -p:GenerateDocumentationFile=false -nowarn:CS1591 --nologo -v quiet 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Host "FAILED"; exit 1 }
    Write-Host '   build OK' -ForegroundColor Green
} finally { Pop-Location }

# Deploy
$src = Get-ChildItem $blseRoot -Recurse -Filter 'Bannerlord.BLSE.Shared.dll' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\bin\\Release\\' -and $_.FullName -notmatch '\\obj\\' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$dst = Join-Path $bin 'Bannerlord.BLSE.Shared.dll'
Copy-Item $src.FullName $dst -Force

Write-Host ''
Write-Host '==> Launch with CWD=bin' -ForegroundColor Cyan
$proc = Start-Process -FilePath $gameLauncher -WorkingDirectory $bin -PassThru
Start-Sleep -Seconds 14
$proc.Refresh()
if ($proc.HasExited) { Write-Host ('   EXITED code=' + $proc.ExitCode) -ForegroundColor Red }
else { Write-Host ('   running ' + $proc.Modules.Count + ' modules') -ForegroundColor Green; Stop-Process -Id $proc.Id -Force }

foreach ($f in @('C:\dev\bannerlord\program-main.log','C:\dev\bannerlord\launcherex-launch.log','C:\dev\bannerlord\manager-enable.log','C:\dev\bannerlord\hide-debug.log')) {
    Write-Host ''
    Write-Host ('==> ' + $f) -ForegroundColor Cyan
    if (Test-Path $f) { Get-Content $f | ForEach-Object { Write-Host ('   ' + $_) -ForegroundColor Green } }
    else { Write-Host '   (not written)' -ForegroundColor Red }
}
