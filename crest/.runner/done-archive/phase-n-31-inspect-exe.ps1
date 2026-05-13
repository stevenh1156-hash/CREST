$ErrorActionPreference = 'Continue'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$cecilDll = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client\Mono.Cecil.dll'
$exe = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.BLSE.LauncherEx.exe'

[Reflection.Assembly]::LoadFrom($cecilDll) | Out-Null

Write-Host "==> Inspecting $exe" -ForegroundColor Cyan
Write-Host ('  size: ' + ([math]::Round((Get-Item $exe).Length/1KB)) + ' KB')

$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($exe)

Write-Host ''
Write-Host '==> Top-level types:' -ForegroundColor Cyan
$asm.MainModule.Types | Where-Object { $_.Name -ne '<Module>' } | Sort-Object FullName | ForEach-Object {
    Write-Host ('   ' + $_.FullName)
}

Write-Host ''
Write-Host '==> Embedded resources:' -ForegroundColor Cyan
$asm.MainModule.Resources | ForEach-Object { Write-Host ('   ' + $_.Name) }

Write-Host ''
Write-Host '==> Entry point:' -ForegroundColor Cyan
$ep = $asm.MainModule.EntryPoint
Write-Host ('   ' + $ep.DeclaringType.FullName + '.' + $ep.Name)
Write-Host '   IL:'
$ep.Body.Instructions | Select-Object -First 20 | ForEach-Object {
    Write-Host ('     ' + $_.OpCode.Name + ' ' + $_.Operand)
}

$asm.Dispose()
