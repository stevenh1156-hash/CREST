$ErrorActionPreference = 'Continue'
$sdkRoot = 'C:\Users\Steve\.nuget\packages\bannerlord.butrmodule.sdk\1.1.0.128'
foreach ($f in @('Sdk\Sdk.targets', 'Sdk\Basic.targets', 'Sdk\Advanced.targets')) {
    $path = Join-Path $sdkRoot $f
    if (Test-Path $path) {
        Write-Host "=== $f ===" -ForegroundColor Cyan
        # Look for AssemblyName-related rules
        $matches = Select-String -Path $path -Pattern 'AssemblyName|GameVersion|ModuleId|ExtendedBuild|Rename|Version|Output' -List
        Write-Host ""
        $hits = Select-String -Path $path -Pattern 'AssemblyName|GameVersion|ExtendedBuild' -Context 1,1
        $hits | Select-Object -First 40 | ForEach-Object {
            Write-Host ("  L{0}: {1}" -f $_.LineNumber, $_.Line.Trim())
        }
        Write-Host ""
    }
}
