$ErrorActionPreference = 'Continue'
$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$bin = Join-Path $gameRoot 'bin\Win64_Shipping_Client'
$logFile = 'C:\dev\bannerlord\appdomain-init.log'
if (Test-Path $logFile) { Remove-Item $logFile -Force }

Push-Location $blseRoot
try {
    Write-Host '==> Building BLSE.Shared (verbose)' -ForegroundColor Cyan
    $output = & dotnet build src\Bannerlord.BLSE.Shared\Bannerlord.BLSE.Shared.csproj `
        --configuration Release -p:GenerateDocumentationFile=false -nowarn:CS1591 --nologo -v minimal 2>&1
    $exit = $LASTEXITCODE
    Write-Host ("   exit=" + $exit) -ForegroundColor (if ($exit -eq 0) { 'Green' } else { 'Red' })
    $output | Where-Object { $_ -match 'error|FAILED|warning|Build succeeded|->' } | Select-Object -Last 20 | ForEach-Object { Write-Host ('   ' + $_) }
    if ($exit -ne 0) { exit 1 }
} finally { Pop-Location }

$src = Get-ChildItem $blseRoot -Recurse -Filter 'Bannerlord.BLSE.Shared.dll' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\bin\\Release\\' -and $_.FullName -notmatch '\\obj\\' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host ''
Write-Host '==> Source DLL fingerprint' -ForegroundColor Cyan
Write-Host ('   ' + $src.FullName)
Write-Host ('   ts: ' + $src.LastWriteTime.ToString('HH:mm:ss') + '  size: ' + ([math]::Round($src.Length/1KB)) + 'KB')

$dst = Join-Path $bin 'Bannerlord.BLSE.Shared.dll'
Copy-Item $src.FullName $dst -Force
$df = Get-Item $dst
Write-Host ('   deployed ts: ' + $df.LastWriteTime.ToString('HH:mm:ss') + '  size: ' + ([math]::Round($df.Length/1KB)) + 'KB')

# Launch
Write-Host ''
Write-Host '==> Launching launcher (Steam path)' -ForegroundColor Cyan
$proc = Start-Process -FilePath (Join-Path $bin 'TaleWorlds.MountAndBlade.Launcher.exe') -WorkingDirectory $bin -PassThru
Start-Sleep -Seconds 14
if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }

Write-Host ''
Write-Host '==> appdomain-init.log:'
if (Test-Path $logFile) { Get-Content $logFile | ForEach-Object { Write-Host ('   ' + $_) } } else { Write-Host '   (none)' -ForegroundColor Red }
