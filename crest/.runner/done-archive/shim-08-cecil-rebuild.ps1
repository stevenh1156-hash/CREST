$ErrorActionPreference = 'Continue'

Write-Host "==> Running shim generator (Cecil 4-arg ctor fix)" -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\shims\generate-shims.ps1'
$exit = $LASTEXITCODE
Write-Host "Generator exit: $exit"

Write-Host ""
Write-Host "==> Generated shim DLLs:" -ForegroundColor Cyan
Get-ChildItem -Recurse -Path 'C:\dev\bannerlord\crest\shims' -Filter '*.dll' -ErrorAction SilentlyContinue |
    Sort-Object Name |
    ForEach-Object { Write-Host ("    {0,9:N0}B  {1}" -f $_.Length, $_.FullName) }

# Verify Bannerlord.Harmony.dll shim has expected forwarders
$harmonyShim = 'C:\dev\bannerlord\crest\shims\Bannerlord.Harmony.Shim\Bannerlord.Harmony.dll'
if (Test-Path $harmonyShim) {
    Add-Type -Path 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'
    $asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($harmonyShim)
    try {
        Write-Host ""
        Write-Host "==> Sanity check Bannerlord.Harmony.dll:" -ForegroundColor Cyan
        Write-Host ("    Assembly: {0} v{1}" -f $asm.Name.Name, $asm.Name.Version)
        Write-Host ("    AssemblyRefs:")
        $asm.MainModule.AssemblyReferences | ForEach-Object { Write-Host ("      -> {0} v{1}" -f $_.Name, $_.Version) }
        Write-Host ("    ExportedTypes: {0}" -f $asm.MainModule.ExportedTypes.Count)
        Write-Host ("    Sample (first 5):")
        $asm.MainModule.ExportedTypes | Select-Object -First 5 | ForEach-Object {
            $fwd = if ($_.IsForwarder) { 'F' } else { '-' }
            $scopeName = if ($_.Scope) { $_.Scope.Name } else { '?' }
            Write-Host ("      [{0}] {1}.{2}  -> {3}" -f $fwd, $_.Namespace, $_.Name, $scopeName)
        }
    } finally { $asm.Dispose() }
}
