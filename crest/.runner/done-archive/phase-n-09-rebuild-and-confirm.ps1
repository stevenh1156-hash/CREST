$ErrorActionPreference = 'Continue'

Write-Host '==> Rebuild BLSE + verify new patch shape' -ForegroundColor Cyan
$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'

# Build
Push-Location $blseRoot
try {
    $args = @(
        'build', 'src/Bannerlord.LauncherEx/Bannerlord.LauncherEx.csproj',
        '--configuration', 'Release_140',
        "-p:GameFolder=$gameRoot",
        '-p:GameVersion=1.4.0',
        '-p:GenerateDocumentationFile=false',
        '-nowarn:CS1591', '--nologo', '-v', 'minimal'
    )
    $output = & dotnet @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "build FAILED" -ForegroundColor Red
        $output | Where-Object { $_ -match 'error|FAILED' } | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        exit 1
    }
    Write-Host '   build OK' -ForegroundColor Green
} finally { Pop-Location }

# Deploy
$src = Join-Path $blseRoot 'src\Bannerlord.LauncherEx\bin\Release_140\netstandard2.0\Bannerlord.LauncherEx.dll'
$dst = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.LauncherEx.dll'
Copy-Item $src $dst -Force
Write-Host ("   deployed " + (Get-Item $dst).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor Green

# Cecil-verify the deployed DLL has the new method shape
$cecilDll = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client\Mono.Cecil.dll'
[Reflection.Assembly]::LoadFrom($cecilDll) | Out-Null
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dst)
$hide = $asm.MainModule.Types | Where-Object { $_.Name -eq 'HideCrestStubsPatch' }
Write-Host ''
Write-Host 'HideCrestStubsPatch methods in deployed DLL:' -ForegroundColor Cyan
foreach ($m in $hide.Methods) {
    $params = ($m.Parameters | ForEach-Object { $_.ParameterType.Name }) -join ', '
    Write-Host ("  " + $m.Name + "(" + $params + ")")
}
$asm.Dispose()

Write-Host ''
Write-Host '==> Done. Relaunch the launcher and check the mod list.' -ForegroundColor Green
