$ErrorActionPreference = 'Continue'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$installBin = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'
$cecilDll = Join-Path $installBin 'Mono.Cecil.dll'
[Reflection.Assembly]::LoadFrom($cecilDll) | Out-Null

foreach ($name in @('CREST.v1.4.1.dll','Crest.MCM.UI.Adapter.MCMv5.dll','Crest.MCM.dll')) {
    $p = Join-Path $installBin $name
    if (-not (Test-Path $p)) { continue }
    Write-Host ("==> " + $name) -ForegroundColor Cyan
    $asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($p)
    $asm.MainModule.GetTypes() | Where-Object { $_.FullName -match 'ModOptions|SettingsVM|Settings' -and $_.IsClass } |
        Select-Object -First 15 |
        ForEach-Object { Write-Host ('   ' + $_.FullName) }
    $asm.Dispose()
    Write-Host ''
}
