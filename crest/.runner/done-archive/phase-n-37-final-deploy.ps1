$ErrorActionPreference = 'Continue'
$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$bin = Join-Path $gameRoot 'bin\Win64_Shipping_Client'
$gameLauncher = Join-Path $bin 'Bannerlord.BLSE.LauncherEx.exe'

Write-Host '==> Final clean build + deploy of HideCrestStubsPatch' -ForegroundColor Cyan

# Delete stale on-disk LauncherEx.dll so the embedded one is used
$staleDll = Join-Path $bin 'Bannerlord.LauncherEx.dll'
if (Test-Path $staleDll) {
    Remove-Item $staleDll -Force
    Write-Host '   removed stale on-disk Bannerlord.LauncherEx.dll' -ForegroundColor Yellow
}

# Rebuild Shared (cascades 5x LauncherEx + embeds)
Push-Location $blseRoot
try {
    Write-Host '   building BLSE.Shared (cascades through 5x LauncherEx variants)' -ForegroundColor DarkGray
    $output = & dotnet build src\Bannerlord.BLSE.Shared\Bannerlord.BLSE.Shared.csproj `
        --configuration Release -p:GenerateDocumentationFile=false -nowarn:CS1591 --nologo -v quiet 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   build FAILED" -ForegroundColor Red
        $output | Where-Object { $_ -match 'error|FAILED' } | Select-Object -First 15 | ForEach-Object { Write-Host "     $_" -ForegroundColor Red }
        exit 1
    }
    Write-Host '   build OK' -ForegroundColor Green
} finally { Pop-Location }

# Deploy fresh BLSE.Shared.dll
$src = Get-ChildItem $blseRoot -Recurse -Filter 'Bannerlord.BLSE.Shared.dll' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\bin\\Release\\' -and $_.FullName -notmatch '\\obj\\' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$dst = Join-Path $bin 'Bannerlord.BLSE.Shared.dll'
Copy-Item $src.FullName $dst -Force
Write-Host ("   deployed Bannerlord.BLSE.Shared.dll (" + ([math]::Round((Get-Item $dst).Length/1KB)) + ' KB, ' + (Get-Item $dst).LastWriteTime.ToString('HH:mm:ss') + ')') -ForegroundColor Green

# Smoke test
Write-Host ''
Write-Host '==> Smoke test: launch and check it stays running' -ForegroundColor Cyan
$proc = Start-Process -FilePath $gameLauncher -WorkingDirectory $bin -PassThru
Start-Sleep -Seconds 14
$proc.Refresh()
if ($proc.HasExited) {
    Write-Host ('   EXITED early code=' + $proc.ExitCode) -ForegroundColor Red
} else {
    Write-Host ('   running ' + $proc.Modules.Count + ' modules') -ForegroundColor Green
    Stop-Process -Id $proc.Id -Force
}

Write-Host ''
Write-Host '==> Done. Open the launcher manually to verify the four stubs are hidden from the mod list.' -ForegroundColor Yellow
