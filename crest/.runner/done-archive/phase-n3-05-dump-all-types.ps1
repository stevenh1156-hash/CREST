$ErrorActionPreference = 'Continue'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$installBin = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'
$cecilDll = Join-Path $installBin 'Mono.Cecil.dll'
[Reflection.Assembly]::LoadFrom($cecilDll) | Out-Null

$p = Join-Path $installBin 'CREST.v1.4.1.dll'
Write-Host ("==> Types in CREST.v1.4.1.dll (" + ([math]::Round((Get-Item $p).Length/1KB)) + " KB):") -ForegroundColor Cyan
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($p)
$count = 0
foreach ($t in $asm.MainModule.GetTypes()) {
    if ($t.FullName -match 'ModOptionsVM|IsCrestInternal|MCM\.UI\.GUI\.ViewModels') {
        Write-Host ('   ' + $t.FullName)
        $count++
    }
}
Write-Host ("   [matched $count types]")
Write-Host ''
Write-Host '   First 20 types in module:'
$asm.MainModule.GetTypes() | Select-Object -First 20 | ForEach-Object { Write-Host ('     ' + $_.FullName) }
$asm.Dispose()
