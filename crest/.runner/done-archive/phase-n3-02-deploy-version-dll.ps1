$ErrorActionPreference = 'Continue'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$staging = 'C:\dev\bannerlord\crest\dist\CREST'
$installBin = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'

# Deploy CREST.v1.4.1.dll too -- the version-specific MCM UI code.
foreach ($name in @('CREST.v1.4.1.dll','Bannerlord.ModuleLoader.CREST.dll')) {
    $src = Join-Path $staging "bin\Win64_Shipping_Client\$name"
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $installBin $name) -Force
        $f = Get-Item (Join-Path $installBin $name)
        Write-Host ("   deployed " + $name + " (" + ([math]::Round($f.Length/1KB)) + " KB, " + $f.LastWriteTime.ToString('HH:mm:ss') + ")") -ForegroundColor Green
    }
}

# Cecil: confirm the IsCrestInternalSettingsId helper made it into the version DLL
$cecilDll = Join-Path $installBin 'Mono.Cecil.dll'
[Reflection.Assembly]::LoadFrom($cecilDll) | Out-Null

Write-Host ''
Write-Host '==> Cecil-verify: which DLL has IsCrestInternalSettingsId?' -ForegroundColor Cyan
foreach ($cand in 'Crest.MCM.UI.Adapter.MCMv5.dll','CREST.v1.4.1.dll') {
    $p = Join-Path $installBin $cand
    if (-not (Test-Path $p)) { continue }
    $asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($p)
    $hits = $asm.MainModule.GetTypes() | ForEach-Object { $_.Methods } | Where-Object { $_.Name -eq 'IsCrestInternalSettingsId' }
    if ($hits) { Write-Host ('   FOUND in ' + $cand) -ForegroundColor Green }
    else { Write-Host ('   not in ' + $cand) -ForegroundColor DarkGray }
    $asm.Dispose()
}

Write-Host ''
Write-Host '==> Open the game and check Mod Options. Should be just CREST + consumer mods.' -ForegroundColor Yellow
