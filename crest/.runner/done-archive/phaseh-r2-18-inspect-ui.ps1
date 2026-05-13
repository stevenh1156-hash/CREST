# Inspect CREST.v1.4.1.dll to find the MCMUISubModule class FQN we need
# in SubModule.xml.
$ErrorActionPreference = 'Stop'

$cecilPath = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'
Add-Type -Path $cecilPath

$dll = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client\CREST.v1.4.1.dll'

if (-not (Test-Path $dll)) {
    Write-Host "MISSING: $dll" -ForegroundColor Red
    exit 1
}

$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dll)
try {
    Write-Host ("Assembly: {0}  v{1}" -f $asm.Name.Name, $asm.Name.Version) -ForegroundColor White
    Write-Host ""
    Write-Host "==> Classes inheriting from MBSubModuleBase:" -ForegroundColor Cyan
    foreach ($t in $asm.MainModule.Types) {
        if ($t.IsPublic -and -not $t.IsNested) {
            $b = $t.BaseType
            $chain = @()
            while ($b -ne $null) {
                $chain += $b.FullName
                if ($b.FullName -eq 'TaleWorlds.MountAndBlade.MBSubModuleBase') {
                    Write-Host ("  {0}.{1}" -f $t.Namespace, $t.Name) -ForegroundColor Green
                    break
                }
                try { $b = $b.Resolve()?.BaseType } catch { $b = $null }
            }
        }
    }
    Write-Host ""
    Write-Host "==> Types in MCM.UI namespace (sample):" -ForegroundColor Cyan
    $asm.MainModule.Types |
        Where-Object { $_.Namespace -like 'MCM.UI*' -and -not $_.IsNested } |
        Select-Object -First 15 |
        ForEach-Object { Write-Host ("  {0}.{1}" -f $_.Namespace, $_.Name) }

    Write-Host ""
    Write-Host "==> Embedded resources count:" -ForegroundColor Cyan
    $resources = @($asm.MainModule.Resources)
    Write-Host ("  total: {0}" -f $resources.Count)
    $resources | Select-Object -First 8 | ForEach-Object { Write-Host ("    {0}" -f $_.Name) }
} finally {
    $asm.Dispose()
}
