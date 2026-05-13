$ErrorActionPreference = 'Continue'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$installBin = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'
$cecilDll = Join-Path $installBin 'Mono.Cecil.dll'
[Reflection.Assembly]::LoadFrom($cecilDll) | Out-Null

$loader = Join-Path $installBin 'Bannerlord.ModuleLoader.CREST.dll'
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($loader)

# Extract ILRepack.List
$res = $asm.MainModule.Resources | Where-Object { $_.Name -eq 'ILRepack.List' }
if ($res) {
    $bytes = $res.GetResourceData()
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    Write-Host '==> ILRepack.List (assemblies merged into ModuleLoader.CREST.dll):' -ForegroundColor Cyan
    $text -split "`n" | ForEach-Object { Write-Host ('   ' + $_) }
}

# Top-level types in loader
Write-Host ''
Write-Host '==> Sample types in ModuleLoader.CREST.dll' -ForegroundColor Cyan
$asm.MainModule.Types | Select-Object -First 20 | ForEach-Object { Write-Host ('   ' + $_.FullName) }

# What does CREST/SubModule.xml actually say?
Write-Host ''
Write-Host '==> SubModule.xml content' -ForegroundColor Cyan
$smXml = Join-Path $gameRoot 'Modules\CREST\SubModule.xml'
Get-Content $smXml | Select-String -Pattern 'DLLName|Assembly' -SimpleMatch | ForEach-Object { Write-Host ('   ' + $_) }

$asm.Dispose()
