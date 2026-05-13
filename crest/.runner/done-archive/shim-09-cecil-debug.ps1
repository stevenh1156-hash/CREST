$ErrorActionPreference = 'Continue'
Add-Type -Path 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'

$dll = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll'
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dll)
try {
    $module = $asm.MainModule
    Write-Host ("Module.Types count: {0}" -f $module.Types.Count)
    Write-Host ("First 25 types and their visibility:")
    $module.Types | Select-Object -First 25 | ForEach-Object {
        $name = "$($_.Namespace).$($_.Name)"
        $isPub = $_.IsPublic
        $isNested = $_.IsNested
        $isNotPublic = $_.IsNotPublic
        $attrs = $_.Attributes -band 0x07  # visibility bits
        Write-Host ("  {0,-60} pub={1,-5} nested={2,-5} notpub={3,-5} attrFlags={4}" -f $name, $isPub, $isNested, $isNotPublic, $attrs)
    }
    Write-Host ""
    Write-Host "Counts by category:"
    $allTop = ($module.Types | Where-Object { -not $_.IsNested }).Count
    $publicTop = ($module.Types | Where-Object { -not $_.IsNested -and $_.IsPublic }).Count
    $internalTop = ($module.Types | Where-Object { -not $_.IsNested -and -not $_.IsPublic }).Count
    Write-Host "  top-level total: $allTop"
    Write-Host "  top-level public: $publicTop"
    Write-Host "  top-level non-public: $internalTop"
} finally { $asm.Dispose() }
