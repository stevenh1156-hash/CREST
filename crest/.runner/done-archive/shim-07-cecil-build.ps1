$ErrorActionPreference = 'Continue'

# Run the pure-Cecil shim generator. Builds Bannerlord.X.dll files directly
# into each shim project's folder.
Write-Host "==> Running pure-Cecil shim generator" -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\shims\generate-shims.ps1'
$exit = $LASTEXITCODE
Write-Host ""
Write-Host "Generator exit code: $exit"

# Verify outputs
Write-Host ""
Write-Host "==> Generated shim DLLs:" -ForegroundColor Cyan
Get-ChildItem -Recurse -Path 'C:\dev\bannerlord\crest\shims' -Filter '*.dll' -ErrorAction SilentlyContinue |
    Sort-Object Name |
    ForEach-Object { Write-Host ("    {0,9:N0}B  {1}" -f $_.Length, $_.FullName) }

# Sanity check one - load via Mono.Cecil and dump exported types count
$harmonyShim = 'C:\dev\bannerlord\crest\shims\Bannerlord.Harmony.Shim\Bannerlord.Harmony.dll'
if (Test-Path $harmonyShim) {
    $cecilPath = (Get-ChildItem -Recurse 'C:\dev\bannerlord' -Filter 'Mono.Cecil.dll' | Select-Object -First 1).FullName
    Add-Type -Path $cecilPath
    $asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($harmonyShim)
    try {
        Write-Host ""
        Write-Host "==> Sanity check on Bannerlord.Harmony.dll shim:" -ForegroundColor Cyan
        Write-Host ("    Assembly: {0} v{1}" -f $asm.Name.Name, $asm.Name.Version)
        Write-Host ("    AssemblyRefs: {0}" -f $asm.MainModule.AssemblyReferences.Count)
        $asm.MainModule.AssemblyReferences | ForEach-Object { Write-Host ("      -> {0} v{1}" -f $_.Name, $_.Version) }
        Write-Host ("    ExportedTypes (forwarders): {0}" -f $asm.MainModule.ExportedTypes.Count)
        # Show first 5
        $asm.MainModule.ExportedTypes | Select-Object -First 5 | ForEach-Object {
            $fwd = if ($_.IsForwarder) { 'F' } else { '-' }
            Write-Host ("      [{0}] {1}.{2}  -> {3}" -f $fwd, $_.Namespace, $_.Name, $_.Scope.Name)
        }
    } finally { $asm.Dispose() }
}
