$ErrorActionPreference = 'Continue'
$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$bin = Join-Path $gameRoot 'bin\Win64_Shipping_Client'

Write-Host '==> Rebuild BLSE.Shared (no longer double-registers BLSE feature patches)' -ForegroundColor Cyan

Push-Location $blseRoot
try {
    $output = & dotnet build src\Bannerlord.BLSE.Shared\Bannerlord.BLSE.Shared.csproj `
        --configuration Release -p:GenerateDocumentationFile=false -nowarn:CS1591 --nologo -v minimal 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED" -ForegroundColor Red
        $output | Where-Object { $_ -match 'error|FAILED' } | Select-Object -First 15 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        exit 1
    }
    Write-Host 'OK' -ForegroundColor Green
} finally { Pop-Location }

# Deploy
$src = Get-ChildItem $blseRoot -Recurse -Filter 'Bannerlord.BLSE.Shared.dll' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\bin\\Release\\' -and $_.FullName -notmatch '\\obj\\' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$dst = Join-Path $bin 'Bannerlord.BLSE.Shared.dll'
Copy-Item $src.FullName $dst -Force
Write-Host ('Deployed at ' + (Get-Item $dst).LastWriteTime.ToString('HH:mm:ss')) -ForegroundColor Green

# Smoke test
Write-Host ''
Write-Host '==> Smoke test launcher (Steam path)' -ForegroundColor Cyan
$proc = Start-Process -FilePath (Join-Path $bin 'TaleWorlds.MountAndBlade.Launcher.exe') -WorkingDirectory $bin -PassThru
Start-Sleep -Seconds 14
$proc.Refresh()
if ($proc.HasExited) { Write-Host ('   EXITED code=' + $proc.ExitCode) -ForegroundColor Red }
else { Write-Host ('   running ' + $proc.Modules.Count + ' modules') -ForegroundColor Green; Stop-Process -Id $proc.Id -Force }

Write-Host ''
Write-Host '==> Now launch via Steam, click Play, and confirm the game loads to main menu without crashing.' -ForegroundColor Yellow
