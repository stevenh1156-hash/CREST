$ErrorActionPreference = 'Continue'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$installBin = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'
$cecilDll = Join-Path $installBin 'Mono.Cecil.dll'
[Reflection.Assembly]::LoadFrom($cecilDll) | Out-Null

foreach ($name in @('CREST.v1.4.1.dll','Crest.MCM.UI.Adapter.MCMv5.dll','Crest.MCM.dll')) {
    $p = Join-Path $installBin $name
    if (-not (Test-Path $p)) { continue }
    Write-Host ("==> " + $name + ' (' + ([math]::Round((Get-Item $p).Length/1KB)) + ' KB)') -ForegroundColor Cyan
    $asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($p)
    # Use .Types directly (top-level types) not GetTypes() extension
    $types = $asm.MainModule.Types
    Write-Host ("   total top-level types: " + $types.Count)
    $hits = $types | Where-Object { $_.Name -eq 'ModOptionsVM' -or $_.FullName -match 'ModOptions' }
    if ($hits) {
        foreach ($t in $hits) {
            Write-Host ('   ' + $t.FullName) -ForegroundColor Green
            foreach ($m in $t.Methods) { Write-Host ('     method: ' + $m.Name) }
        }
    } else {
        Write-Host '   no ModOptions* types'
    }
    $asm.Dispose()
}
