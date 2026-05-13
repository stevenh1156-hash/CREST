$ErrorActionPreference = 'Continue'
$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$bin = Join-Path $gameRoot 'bin\Win64_Shipping_Client'

Write-Host '==> Build BLSE.Shared (with TaleWorlds-launcher hide patch)' -ForegroundColor Cyan
Push-Location $blseRoot
try {
    $output = & dotnet build src\Bannerlord.BLSE.Shared\Bannerlord.BLSE.Shared.csproj `
        --configuration Release -p:GenerateDocumentationFile=false -nowarn:CS1591 --nologo -v quiet 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "build FAILED" -ForegroundColor Red
        $output | Where-Object { $_ -match 'error|FAILED' } | Select-Object -First 25 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
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
Write-Host ('   deployed BLSE.Shared.dll at ' + (Get-Item $dst).LastWriteTime.ToString('HH:mm:ss')) -ForegroundColor Green

# Cecil-verify the new patch class is in the deployed DLL
$cecilDll = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client\Mono.Cecil.dll'
[Reflection.Assembly]::LoadFrom($cecilDll) | Out-Null
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dst)
$hide = $asm.MainModule.Types | Where-Object { $_.Name -eq 'HideCrestStubsFromTaleWorldsLauncher' }
if ($hide) {
    Write-Host '   HideCrestStubsFromTaleWorldsLauncher present in BLSE.Shared:' -ForegroundColor Green
    foreach ($m in $hide.Methods) { Write-Host ('     ' + $m.Name) }
}
$asm.Dispose()

Write-Host ''
Write-Host '==> Smoke test: launch via TaleWorlds.MountAndBlade.Launcher.exe (Steam path)' -ForegroundColor Cyan
$twLauncher = Join-Path $bin 'TaleWorlds.MountAndBlade.Launcher.exe'
$proc = Start-Process -FilePath $twLauncher -WorkingDirectory $bin -PassThru
Start-Sleep -Seconds 14
$proc.Refresh()
if ($proc.HasExited) { Write-Host ('   EXITED code=' + $proc.ExitCode) -ForegroundColor Red }
else { Write-Host ('   running ' + $proc.Modules.Count + ' modules') -ForegroundColor Green; Stop-Process -Id $proc.Id -Force }

Write-Host ''
Write-Host '==> Open the launcher manually via Steam to verify stubs are now hidden.' -ForegroundColor Yellow
