$ErrorActionPreference = 'Continue'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$cecilDll = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client\Mono.Cecil.dll'
$launcherLib = Join-Path $gameRoot 'bin\Win64_Shipping_Client\TaleWorlds.MountAndBlade.Launcher.Library.dll'

[Reflection.Assembly]::LoadFrom($cecilDll) | Out-Null

Write-Host '==> Inspecting TaleWorlds.MountAndBlade.Launcher.Library.LauncherModsVM' -ForegroundColor Cyan
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($launcherLib)

$vm = $asm.MainModule.Types | Where-Object { $_.Name -eq 'LauncherModsVM' }
if (-not $vm) { Write-Host '   NOT FOUND' -ForegroundColor Red; exit 1 }

Write-Host ('   FullName: ' + $vm.FullName)
Write-Host ''
Write-Host '   Properties (likely UI bindings):' -ForegroundColor Yellow
$vm.Properties | ForEach-Object { Write-Host ('     ' + $_.PropertyType.Name + ' ' + $_.Name) }
Write-Host ''
Write-Host '   Fields:' -ForegroundColor Yellow
$vm.Fields | ForEach-Object { Write-Host ('     ' + $_.FieldType.Name + ' ' + $_.Name) }
Write-Host ''
Write-Host '   Methods:' -ForegroundColor Yellow
$vm.Methods | Where-Object { -not $_.IsConstructor } | ForEach-Object {
    $params = ($_.Parameters | ForEach-Object { $_.ParameterType.Name + ' ' + $_.Name }) -join ', '
    Write-Host ('     ' + $_.ReturnType.Name + ' ' + $_.Name + '(' + $params + ')')
}

Write-Host ''
Write-Host '==> LauncherModuleVM type (per-mod VM)' -ForegroundColor Cyan
$mod = $asm.MainModule.Types | Where-Object { $_.Name -eq 'LauncherModuleVM' }
if ($mod) {
    Write-Host ('   FullName: ' + $mod.FullName)
    Write-Host '   Properties:'
    $mod.Properties | ForEach-Object { Write-Host ('     ' + $_.PropertyType.Name + ' ' + $_.Name) }
    Write-Host '   Fields with id/name semantic:'
    $mod.Fields | Where-Object { $_.Name -match 'Id|Name|Module|Info' } | ForEach-Object { Write-Host ('     ' + $_.FieldType.Name + ' ' + $_.Name) }
}

$asm.Dispose()
