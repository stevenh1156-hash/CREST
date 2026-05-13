$ErrorActionPreference = 'Continue'
$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$bin = Join-Path $gameRoot 'bin\Win64_Shipping_Client'
$gameLauncher = Join-Path $bin 'Bannerlord.BLSE.LauncherEx.exe'

foreach ($f in @('C:\dev\bannerlord\launcherex-launch.log','C:\dev\bannerlord\manager-enable.log')) { if (Test-Path $f) { Remove-Item $f -Force } }

Push-Location $blseRoot
try {
    $null = & dotnet build src\Bannerlord.BLSE.Shared\Bannerlord.BLSE.Shared.csproj --configuration Release -p:GenerateDocumentationFile=false -nowarn:CS1591 --nologo -v quiet 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Host "FAILED build"; exit 1 }
} finally { Pop-Location }

$src = Get-ChildItem $blseRoot -Recurse -Filter 'Bannerlord.BLSE.Shared.dll' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\bin\\Release\\' -and $_.FullName -notmatch '\\obj\\' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
Copy-Item $src.FullName (Join-Path $bin 'Bannerlord.BLSE.Shared.dll') -Force

$proc = Start-Process -FilePath $gameLauncher -WorkingDirectory $bin -PassThru
Start-Sleep -Seconds 14
if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }

Write-Host '==> launcherex-launch.log:'
if (Test-Path 'C:\dev\bannerlord\launcherex-launch.log') {
    Get-Content 'C:\dev\bannerlord\launcherex-launch.log' | ForEach-Object { Write-Host ('   ' + $_) }
}
Write-Host ''
Write-Host '==> manager-enable.log:'
if (Test-Path 'C:\dev\bannerlord\manager-enable.log') {
    Get-Content 'C:\dev\bannerlord\manager-enable.log' | ForEach-Object { Write-Host ('   ' + $_) }
} else { Write-Host '   (none)' }
