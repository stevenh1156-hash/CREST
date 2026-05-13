$ErrorActionPreference = 'Continue'

Write-Host '==> Rebuild + redeploy BLSE LauncherEx with new HideCrestStubsPatch' -ForegroundColor Cyan

$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'

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
        Write-Host "FAILED exit=$LASTEXITCODE" -ForegroundColor Red
        $output | Where-Object { $_ -match 'error|FAILED' } | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        exit 1
    }
    Write-Host '   build OK' -ForegroundColor Green
} finally { Pop-Location }

# Deploy
$src = Join-Path $blseRoot 'src\Bannerlord.LauncherEx\bin\Release_140\netstandard2.0\Bannerlord.LauncherEx.dll'
$dst = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.LauncherEx.dll'
Copy-Item $src $dst -Force
$f = Get-Item $dst
Write-Host ("   deployed " + $f.FullName + " (" + ([math]::Round($f.Length/1KB)) + " KB, " + $f.LastWriteTime.ToString('HH:mm:ss') + ")") -ForegroundColor Green

# Verify the new approach is in the deployed DLL
Write-Host ''
Write-Host '==> Verify new patch shape' -ForegroundColor Cyan
$cecilDll = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client\Mono.Cecil.dll'
[Reflection.Assembly]::LoadFrom($cecilDll) | Out-Null
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dst)
$hide = $asm.MainModule.Types | Where-Object { $_.Name -eq 'HideCrestStubsPatch' }
foreach ($m in $hide.Methods) {
    Write-Host ("   method: " + $m.Name)
}
$asm.Dispose()
