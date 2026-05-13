$ErrorActionPreference = 'Continue'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$installBin = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'
$cecilDll = Join-Path $installBin 'Mono.Cecil.dll'

[Reflection.Assembly]::LoadFrom($cecilDll) | Out-Null

Write-Host '==> Search every deployed CREST DLL for type ModOptionsVM' -ForegroundColor Cyan
foreach ($f in Get-ChildItem $installBin -Filter '*.dll') {
    try {
        $asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($f.FullName)
        $hit = $asm.MainModule.GetTypes() | Where-Object { $_.Name -eq 'ModOptionsVM' }
        if ($hit) {
            Write-Host ('   FOUND ModOptionsVM in ' + $f.Name) -ForegroundColor Green
            $methods = $hit.Methods | Select-Object -ExpandProperty Name
            if ($methods -contains 'IsCrestInternalSettingsId') {
                Write-Host '     -> IsCrestInternalSettingsId is present (build has the change)' -ForegroundColor Green
            } else {
                Write-Host '     -> IsCrestInternalSettingsId NOT present (stale build)' -ForegroundColor Red
            }
        }
        $asm.Dispose()
    } catch { }
}

Write-Host ''
Write-Host '==> Search the build outputs for the same' -ForegroundColor Cyan
foreach ($f in Get-ChildItem 'C:\dev\bannerlord\Bannerlord.MBOptionScreen' -Recurse -Filter '*.dll' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '\\bin\\Stable_Release\\' -and $_.FullName -notmatch '\\obj\\' }) {
    try {
        $asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($f.FullName)
        $hit = $asm.MainModule.GetTypes() | Where-Object { $_.Name -eq 'ModOptionsVM' }
        if ($hit) {
            $methods = $hit.Methods | Select-Object -ExpandProperty Name
            $hasMine = $methods -contains 'IsCrestInternalSettingsId'
            Write-Host ('   ' + $f.FullName.Substring($f.FullName.IndexOf('Bannerlord.MBOptionScreen'))) -ForegroundColor White
            Write-Host ('     ts=' + $f.LastWriteTime.ToString('HH:mm:ss') + '  has IsCrestInternalSettingsId? ' + $hasMine)
        }
        $asm.Dispose()
    } catch { }
}
