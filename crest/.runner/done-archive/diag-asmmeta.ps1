$ErrorActionPreference = 'Continue'
Add-Type -Path 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'

$dlls = @(
    'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll',
    'C:\dev\bannerlord\Bannerlord.ButterLib\src\Crest.ButterLib\bin\Release\net472\Crest.ButterLib.dll',
    'C:\dev\bannerlord\Bannerlord.UIExtenderEx\src\Crest.UIExtenderEx\bin\Release\netstandard2.0\Crest.UIExtenderEx.dll',
    'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src\Crest.MCM\bin\Release\netstandard2.0\Crest.MCM.dll'
)

foreach ($d in $dlls) {
    if (-not (Test-Path $d)) { continue }
    Write-Host ""
    Write-Host "==== $(Split-Path $d -Leaf) ====" -ForegroundColor Cyan
    $asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($d)
    try {
        # Walk all assembly-level CustomAttributes
        Write-Host "  AssemblyName: $($asm.Name.Name) v$($asm.Name.Version)"
        $metaAttrs = $asm.CustomAttributes | Where-Object { $_.AttributeType.Name -eq 'AssemblyMetadataAttribute' }
        Write-Host "  AssemblyMetadata count: $($metaAttrs.Count)"
        foreach ($a in $metaAttrs) {
            $key = $a.ConstructorArguments[0].Value
            $val = $a.ConstructorArguments[1].Value
            Write-Host ("    {0,-30} = {1}" -f $key, $val)
        }
    } finally { $asm.Dispose() }
}
