$ErrorActionPreference = 'Continue'
$outFile = 'C:\dev\bannerlord\crest\diag-output.txt'
'Cecil-based DLL inspection - ' + (Get-Date -Format 'HH:mm:ss') | Set-Content $outFile

$bin = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client'
Add-Type -Path (Join-Path $bin 'Mono.Cecil.dll')

function Inspect-Dll($path) {
    if (-not (Test-Path $path)) {
        "  NOT FOUND: $path" | Add-Content $outFile
        return
    }
    try {
        $asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($path)
        $name = $asm.Name.Name
        "  Assembly: $name v$($asm.Name.Version)" | Add-Content $outFile

        # All SubModule classes
        $types = @()
        foreach ($mod in $asm.Modules) {
            foreach ($t in $mod.Types) {
                $types += $t
                # Also nested types (BUTR generates nested loader stubs)
                foreach ($n in $t.NestedTypes) { $types += $n }
            }
        }
        $smTypes = $types | Where-Object { $_.FullName -like '*SubModule*' -or $_.FullName -like '*ModuleLoader*' }
        if ($smTypes) {
            "  SubModule/ModuleLoader types:" | Add-Content $outFile
            foreach ($t in $smTypes) {
                $base = ''
                if ($t.BaseType) { $base = " : $($t.BaseType.Name)" }
                "    - $($t.FullName)$base" | Add-Content $outFile
            }
        }
        $asm.Dispose()
    } catch {
        "  Cecil error: $_" | Add-Content $outFile
    }
}

# Inspect each DLL the SubModule.xml references
$xml = [xml](Get-Content 'C:\dev\bannerlord\crest\dist\CREST\SubModule.xml' -Raw)
foreach ($s in $xml.Module.SubModules.SubModule) {
    "" | Add-Content $outFile
    "=== $($s.Name.value) ===" | Add-Content $outFile
    "  SubModule.xml says DLLName=$($s.DLLName.value), class=$($s.SubModuleClassType.value)" | Add-Content $outFile
    Inspect-Dll (Join-Path $bin $s.DLLName.value)
}

# Also inspect CREST.v1.4.1.dll (referenced as Assembly, holds the actual MCM.UI code)
"" | Add-Content $outFile
"=== CREST.v1.4.1.dll (the versioned MCM.UI body) ===" | Add-Content $outFile
Inspect-Dll (Join-Path $bin 'CREST.v1.4.1.dll')

# And Crest.MCM.UI.Adapter.MCMv5.dll
"" | Add-Content $outFile
"=== Crest.MCM.UI.Adapter.MCMv5.dll ===" | Add-Content $outFile
Inspect-Dll (Join-Path $bin 'Crest.MCM.UI.Adapter.MCMv5.dll')

"" | Add-Content $outFile
"=== Done ===" | Add-Content $outFile
