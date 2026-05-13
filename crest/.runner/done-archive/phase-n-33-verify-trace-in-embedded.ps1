$ErrorActionPreference = 'Continue'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$cecilDll = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client\Mono.Cecil.dll'
$shared = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.BLSE.Shared.dll'
[Reflection.Assembly]::LoadFrom($cecilDll) | Out-Null

$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($shared)
Write-Host ('Shared.dll timestamp: ' + (Get-Item $shared).LastWriteTime.ToString('HH:mm:ss'))

$res = $asm.MainModule.Resources | Where-Object { $_.Name -match 'v1\.4\.0' } | Select-Object -First 1
$bytes = $res.GetResourceData()
$ms = New-Object System.IO.MemoryStream(,$bytes)
$gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
$out = New-Object System.IO.MemoryStream
$gz.CopyTo($out)
$tmp = Join-Path $env:TEMP 'launcherex-extracted2.dll'
[System.IO.File]::WriteAllBytes($tmp, $out.ToArray())

$ext = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($tmp)
$mgr = $ext.MainModule.Types | Where-Object { $_.Name -eq 'Manager' -and $_.Namespace -eq 'Bannerlord.LauncherEx' }
$enable = $mgr.Methods | Where-Object { $_.Name -eq 'Enable' }
Write-Host 'Manager.Enable IL strings:' -ForegroundColor Cyan
$enable.Body.Instructions | Where-Object { $_.Operand -is [string] } | Select-Object -First 10 | ForEach-Object {
    Write-Host ('   "' + $_.Operand + '"')
}

# Also dump any field reads to see if our trace lines made it through
Write-Host ''
Write-Host 'Method calls in Manager.Enable:' -ForegroundColor Cyan
$enable.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] } |
    Select-Object -First 15 | ForEach-Object {
        Write-Host ('   ' + $_.Operand.DeclaringType.Name + '::' + $_.Operand.Name)
    }
