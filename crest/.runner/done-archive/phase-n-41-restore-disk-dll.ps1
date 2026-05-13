$ErrorActionPreference = 'Continue'
$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$bin = Join-Path $gameRoot 'bin\Win64_Shipping_Client'

Write-Host '==> Build fresh Bannerlord.LauncherEx.dll (Release_140) WITH my patches' -ForegroundColor Cyan
Push-Location $blseRoot
try {
    $output = & dotnet build src\Bannerlord.LauncherEx\Bannerlord.LauncherEx.csproj `
        --configuration Release_140 `
        "-p:GameFolder=$gameRoot" `
        '-p:GameVersion=1.4.0' `
        -p:GenerateDocumentationFile=false `
        -nowarn:CS1591 --nologo -v quiet 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "build FAILED" -ForegroundColor Red
        $output | Where-Object { $_ -match 'error|FAILED' } | Select-Object -First 15 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        exit 1
    }
    Write-Host '   build OK' -ForegroundColor Green
} finally { Pop-Location }

# Deploy the fresh-built LauncherEx.dll to game bin (the on-disk path that
# the Steam launch path's assembly resolver finds)
$src = Join-Path $blseRoot 'src\Bannerlord.LauncherEx\bin\Release_140\netstandard2.0\Bannerlord.LauncherEx.dll'
$dst = Join-Path $bin 'Bannerlord.LauncherEx.dll'
if (Test-Path $src) {
    Copy-Item $src $dst -Force
    $f = Get-Item $dst
    Write-Host ("   deployed " + $dst + ' (' + ([math]::Round($f.Length/1KB)) + ' KB, ' + $f.LastWriteTime.ToString('HH:mm:ss') + ')') -ForegroundColor Green
} else {
    Write-Host '   ERROR: built DLL not found' -ForegroundColor Red
    exit 1
}

# Cecil-verify the patch is in there
$cecilDll = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client\Mono.Cecil.dll'
[Reflection.Assembly]::LoadFrom($cecilDll) | Out-Null
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dst)
$hide = $asm.MainModule.Types | Where-Object { $_.Name -eq 'HideCrestStubsPatch' }
if ($hide) {
    Write-Host ''
    Write-Host '   HideCrestStubsPatch present in on-disk DLL:' -ForegroundColor Green
    foreach ($m in $hide.Methods) { Write-Host ('     ' + $m.Name) }
}
$asm.Dispose()
