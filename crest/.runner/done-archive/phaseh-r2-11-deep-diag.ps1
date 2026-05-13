# Deep diagnostic for the BloodMod1313 dependency conflict.
# 1. Tail runtime.log fully (not just last 60)
# 2. Inspect BloodMod1313.dll's assembly references and dependent versions
# 3. Inspect each shim DLL's AssemblyName and version
# 4. Check whether shims successfully load by listing types they expose

$ErrorActionPreference = 'Continue'

$gameModules = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules'
$runtimeLog  = 'C:\dev\bannerlord\crest\runtime.log'
$cecilPath   = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'
Add-Type -Path $cecilPath

Write-Host "==> 1. runtime.log: tail since launch (showing entries with BloodMod, Bannerlord.Harmony shim, Bannerlord.ButterLib shim, Bannerlord.UIExtenderEx shim, MCMv5)" -ForegroundColor Cyan
if (Test-Path $runtimeLog) {
    $logSize = (Get-Item $runtimeLog).Length
    Write-Host ("  runtime.log size: {0:N0} bytes" -f $logSize)
    $lines = Get-Content $runtimeLog
    Write-Host ("  total lines: {0}" -f $lines.Count)
    Write-Host ""
    Write-Host "  -- Last LOAD entries (last 40) --" -ForegroundColor Cyan
    $lines | Where-Object { $_ -match 'LOAD\s' } | Select-Object -Last 40 | ForEach-Object { Write-Host "    $_" }
    Write-Host ""
    Write-Host "  -- All RESOLVE-MISS entries --" -ForegroundColor Cyan
    $lines | Where-Object { $_ -match 'RESOLVE-MISS' } | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "  -- All FIRST-CHANCE TypeLoadException / FileNotFound --" -ForegroundColor Cyan
    $lines | Where-Object { $_ -match 'TypeLoadException|FileNotFoundException|BadImageFormat' } | Select-Object -First 30 | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "  -- Last 20 lines (raw tail) --" -ForegroundColor Cyan
    $lines | Select-Object -Last 20 | ForEach-Object { Write-Host "    $_" }
} else {
    Write-Host "  not found" -ForegroundColor Red
}

Write-Host ""
Write-Host "==> 2. BloodMod1313.dll: AssemblyReferences and version expectations" -ForegroundColor Cyan
$bmDll = Join-Path $gameModules 'BloodMod1313\bin\Win64_Shipping_Client\BloodMod1313.dll'
if (Test-Path $bmDll) {
    $asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($bmDll)
    try {
        Write-Host ("  Assembly: {0}  version {1}" -f $asm.Name.Name, $asm.Name.Version)
        Write-Host "  References:"
        foreach ($r in $asm.MainModule.AssemblyReferences) {
            $tok = ''
            if ($r.PublicKeyToken -and $r.PublicKeyToken.Length -gt 0) {
                $tok = ' tok=' + ([BitConverter]::ToString($r.PublicKeyToken).Replace('-',''))
            }
            Write-Host ("    {0,-40}  v{1}{2}" -f $r.Name, $r.Version, $tok)
        }
    } finally { $asm.Dispose() }
} else {
    Write-Host "  BloodMod1313.dll not found at $bmDll" -ForegroundColor Red
}

Write-Host ""
Write-Host "==> 3. Shim DLLs: AssemblyName, version, exported type sample" -ForegroundColor Cyan
$shims = @(
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client\Bannerlord.Harmony.dll',
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client\Bannerlord.ButterLib.dll',
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client\Bannerlord.UIExtenderEx.dll',
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client\MCMv5.dll'
)
foreach ($s in $shims) {
    if (-not (Test-Path $s)) {
        Write-Host "  MISSING: $s" -ForegroundColor Red
        continue
    }
    $asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($s)
    try {
        Write-Host ""
        Write-Host ("  [{0}] v{1}" -f $asm.Name.Name, $asm.Name.Version) -ForegroundColor White
        $exports = @($asm.MainModule.ExportedTypes)
        Write-Host ("    exported types: {0}" -f $exports.Count)
        if ($exports.Count -gt 0) {
            $exports | Select-Object -First 5 | ForEach-Object {
                $sn = $_.Scope.Name
                Write-Host ("      {0}.{1}  ->  {2}" -f $_.Namespace, $_.Name, $sn)
            }
        }
    } finally { $asm.Dispose() }
}
