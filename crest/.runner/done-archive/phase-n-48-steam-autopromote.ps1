$ErrorActionPreference = 'Continue'
$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$bin = Join-Path $gameRoot 'bin\Win64_Shipping_Client'

Write-Host '==> Build all BLSE projects so Steam-launch path bootstraps the BUTR launcher' -ForegroundColor Cyan

$projects = @(
    'src\Bannerlord.BLSE.Shared\Bannerlord.BLSE.Shared.csproj',
    'src\Bannerlord.BLSE.Loaders.AppDomainManager\Bannerlord.BLSE.Loaders.AppDomainManager.csproj'
)

Push-Location $blseRoot
try {
    foreach ($p in $projects) {
        $name = Split-Path $p -Leaf
        Write-Host ("  building " + $name) -ForegroundColor DarkCyan
        $output = & dotnet build $p --configuration Release `
            -p:GenerateDocumentationFile=false -nowarn:CS1591 --nologo -v minimal 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    FAILED" -ForegroundColor Red
            $output | Where-Object { $_ -match 'error|FAILED' } | Select-Object -First 15 | ForEach-Object { Write-Host "      $_" -ForegroundColor Red }
            exit 1
        }
        Write-Host '    OK' -ForegroundColor Green
    }
} finally { Pop-Location }

# Deploy BLSE.Shared.dll
$src = Get-ChildItem $blseRoot -Recurse -Filter 'Bannerlord.BLSE.Shared.dll' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\bin\\Release\\' -and $_.FullName -notmatch '\\obj\\' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$dst = Join-Path $bin 'Bannerlord.BLSE.Shared.dll'
Copy-Item $src.FullName $dst -Force
Write-Host ('   BLSE.Shared.dll deployed at ' + (Get-Item $dst).LastWriteTime.ToString('HH:mm:ss')) -ForegroundColor Green

# Deploy BLSE.AppDomainManager.dll
$src2 = Get-ChildItem $blseRoot -Recurse -Filter 'Bannerlord.BLSE.AppDomainManager.dll' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\bin\\Release\\' -and $_.FullName -notmatch '\\obj\\' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($src2) {
    $dst2 = Join-Path $bin 'Bannerlord.BLSE.AppDomainManager.dll'
    Copy-Item $src2.FullName $dst2 -Force
    Write-Host ('   BLSE.AppDomainManager.dll deployed at ' + (Get-Item $dst2).LastWriteTime.ToString('HH:mm:ss')) -ForegroundColor Green
}

# Smoke test via TaleWorlds.MountAndBlade.Launcher.exe (Steam path)
Write-Host ''
Write-Host '==> Smoke test: launch TaleWorlds.MountAndBlade.Launcher.exe (Steam path)' -ForegroundColor Cyan
$proc = Start-Process -FilePath (Join-Path $bin 'TaleWorlds.MountAndBlade.Launcher.exe') -WorkingDirectory $bin -PassThru
Start-Sleep -Seconds 14
$proc.Refresh()
if ($proc.HasExited) { Write-Host ('   EXITED code=' + $proc.ExitCode) -ForegroundColor Red }
else { Write-Host ('   running ' + $proc.Modules.Count + ' modules -- launcher loads cleanly') -ForegroundColor Green; Stop-Process -Id $proc.Id -Force }

Write-Host ''
Write-Host '==> Now launch via Steam. You should see the full BUTR launcher (with BLSE version label) and stubs hidden.' -ForegroundColor Yellow
