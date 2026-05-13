# Inspect each shipped DLL's exported types to verify SubModule.xml references resolve.
$ErrorActionPreference = 'Continue'
$outFile = 'C:\dev\bannerlord\crest\diag-output.txt'

'DLL inspection - ' + (Get-Date -Format 'HH:mm:ss') | Set-Content $outFile

$bin = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client'
$xml = [xml](Get-Content 'C:\dev\bannerlord\crest\dist\CREST\SubModule.xml' -Raw)

# For each SubModule entry, look up its DLLName and find the class
foreach ($s in $xml.Module.SubModules.SubModule) {
    $name = $s.Name.value
    $dll = $s.DLLName.value
    $classFqn = $s.SubModuleClassType.value
    "" | Add-Content $outFile
    "=== $name ===" | Add-Content $outFile
    "  DLLName=$dll" | Add-Content $outFile
    "  Required class: $classFqn" | Add-Content $outFile

    $dllPath = Join-Path $bin $dll
    if (-not (Test-Path $dllPath)) {
        "  DLL NOT FOUND" | Add-Content $outFile
        continue
    }

    try {
        # Use ReflectionOnly so we don't actually run static initializers
        $asm = [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($dllPath)
        "  Assembly name: $($asm.GetName().Name) v$($asm.GetName().Version)" | Add-Content $outFile

        # Try to find the required class
        $type = $asm.GetTypes() | Where-Object { $_.FullName -eq $classFqn } | Select-Object -First 1
        if ($type) {
            "  CLASS FOUND: $($type.FullName)" | Add-Content $outFile
        } else {
            "  CLASS NOT FOUND IN $dll" | Add-Content $outFile
            "  Types ending in 'SubModule' in this DLL:" | Add-Content $outFile
            $asm.GetTypes() | Where-Object { $_.Name -like '*SubModule*' } | Select-Object -First 20 | ForEach-Object {
                "    - $($_.FullName)" | Add-Content $outFile
            }
        }
    } catch [System.Reflection.ReflectionTypeLoadException] {
        "  ReflectionTypeLoadException: $($_.Exception.Message)" | Add-Content $outFile
        # The exception has LoaderExceptions with details about which dependent assemblies are missing
        if ($_.Exception.LoaderExceptions) {
            $_.Exception.LoaderExceptions | Select-Object -First 5 | ForEach-Object {
                "    LoaderException: $($_.Message)" | Add-Content $outFile
            }
        }
        # Still try to enumerate types we CAN load
        try {
            $partial = $_.Exception.Types | Where-Object { $_ -ne $null }
            if ($partial) {
                "  Partial type list (those that loaded):" | Add-Content $outFile
                $partial | Where-Object { $_.Name -like '*SubModule*' } | ForEach-Object {
                    "    - $($_.FullName)" | Add-Content $outFile
                }
            }
        } catch {}
    } catch {
        "  Reflection error: $_" | Add-Content $outFile
    }
}

# Also: list ALL types matching 'SubModule' across every shipped DLL
"" | Add-Content $outFile
"=== All *SubModule classes across shipped DLLs ===" | Add-Content $outFile
foreach ($f in (Get-ChildItem $bin -Filter '*.dll' | Sort-Object Name)) {
    try {
        $asm = [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($f.FullName)
        $hits = $asm.GetTypes() | Where-Object { $_.Name -like '*SubModule*' }
        if ($hits) {
            "  $($f.Name):" | Add-Content $outFile
            foreach ($t in $hits) {
                "    - $($t.FullName)" | Add-Content $outFile
            }
        }
    } catch [System.Reflection.ReflectionTypeLoadException] {
        $partial = $_.Exception.Types | Where-Object { $_ -ne $null -and $_.Name -like '*SubModule*' }
        if ($partial) {
            "  $($f.Name) (partial - reflection issues):" | Add-Content $outFile
            foreach ($t in $partial) {
                "    - $($t.FullName)" | Add-Content $outFile
            }
        }
    } catch {
        "  $($f.Name): cannot inspect ($_)" | Add-Content $outFile
    }
}
