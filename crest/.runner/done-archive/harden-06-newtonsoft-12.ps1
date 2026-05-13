$ErrorActionPreference = 'Continue'

$crestDir = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'
$bin = Join-Path $crestDir 'bin\Win64_Shipping_Client'

# Replace Newtonsoft.Json.dll with the v12.0.0.0 BEW expects.
# BEW ships its own copy in its bin folder.
$bewNewton = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\BetterExceptionWindow\bin\Win64_Shipping_Client\Newtonsoft.Json.dll'
if (Test-Path $bewNewton) {
    Copy-Item $bewNewton -Destination $bin -Force
    $info = Get-Item (Join-Path $bin 'Newtonsoft.Json.dll')
    $verInfo = $info.VersionInfo
    Write-Host ("==> Replaced Newtonsoft.Json.dll: {0:N1}KB, FileVersion={1}, ProductVersion={2}" -f ($info.Length/1KB), $verInfo.FileVersion, $verInfo.ProductVersion)
} else {
    Write-Host "BEW's Newtonsoft.Json.dll not found at $bewNewton" -ForegroundColor Red
    exit 1
}

# Confirm assembly identity via Cecil
Add-Type -Path (Join-Path $bin 'Mono.Cecil.dll')
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $bin 'Newtonsoft.Json.dll'))
Write-Host ("    Assembly identity: {0} v{1}" -f $asm.Name.Name, $asm.Name.Version)
$asm.Dispose()

Write-Host ""
Write-Host "==> Try launching. Same launcher state (CREST + Native)."
Write-Host "    If still crashes, the issue is something else (probably 0Harmony binding"
Write-Host "    or a TaleWorlds API mismatch)."
exit 0
