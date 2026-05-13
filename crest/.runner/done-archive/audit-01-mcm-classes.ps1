# Cecil-inspect every Crest.MCM-related DLL to see which class lives where.
$ErrorActionPreference = 'Continue'
$outFile = 'C:\dev\bannerlord\crest\diag-output.txt'
'MCM class location audit - ' + (Get-Date -Format 'HH:mm:ss') | Set-Content $outFile

$bin = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client'
Add-Type -Path (Join-Path $bin 'Mono.Cecil.dll')

$dllsToInspect = @(
    'Crest.MCM.dll',
    'Crest.MCM.UI.Adapter.MCMv5.dll',
    'CREST.v1.4.1.dll',
    'Bannerlord.ModuleLoader.CREST.dll'
)

foreach ($dll in $dllsToInspect) {
    $p = Join-Path $bin $dll
    "" | Add-Content $outFile
    "=== $dll ===" | Add-Content $outFile
    if (-not (Test-Path $p)) { "  NOT FOUND" | Add-Content $outFile; continue }
    try {
        $asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($p)
        "  AssemblyName: $($asm.Name.Name) v$($asm.Name.Version)" | Add-Content $outFile
        $smTypes = @()
        foreach ($mod in $asm.Modules) {
            foreach ($t in $mod.Types) {
                $smTypes += $t
                foreach ($n in $t.NestedTypes) { $smTypes += $n }
            }
        }
        $candidates = $smTypes | Where-Object { $_.FullName -like '*SubModule*' -or $_.FullName -like '*ModuleLoader*' -or $_.FullName -like '*MCMSubModule*' -or $_.FullName -like '*MCMImplementation*' -or $_.FullName -like '*MCMUIAdapter*' -or $_.FullName -like '*MCMUI*SubModule*' }
        if ($candidates) {
            "  Candidate classes (any *SubModule* / *ModuleLoader* / *MCMUI*):" | Add-Content $outFile
            foreach ($t in $candidates) {
                $base = ''
                if ($t.BaseType) { $base = " : $($t.BaseType.Name)" }
                "    $($t.FullName)$base" | Add-Content $outFile
            }
        } else {
            "  (no SubModule-like classes)" | Add-Content $outFile
        }
        $asm.Dispose()
    } catch {
        "  Cecil error: $_" | Add-Content $outFile
    }
}

"" | Add-Content $outFile
"=== Done ===" | Add-Content $outFile
