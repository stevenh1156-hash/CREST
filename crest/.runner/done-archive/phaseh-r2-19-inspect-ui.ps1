$ErrorActionPreference = 'Stop'

$cecilPath = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'
Add-Type -Path $cecilPath

$dll = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client\CREST.v1.4.1.dll'

$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dll)
try {
    Write-Host ("Assembly: {0}  v{1}" -f $asm.Name.Name, $asm.Name.Version) -ForegroundColor White

    Write-Host ""
    Write-Host "==> Classes inheriting (transitively) from MBSubModuleBase:" -ForegroundColor Cyan
    foreach ($t in $asm.MainModule.Types) {
        if ($t.IsNested) { continue }
        if (-not $t.IsPublic) { continue }
        $cur = $t.BaseType
        $depth = 0
        while ($cur -ne $null -and $depth -lt 5) {
            if ($cur.FullName -eq 'TaleWorlds.MountAndBlade.MBSubModuleBase') {
                Write-Host ("  {0}.{1}" -f $t.Namespace, $t.Name) -ForegroundColor Green
                break
            }
            try {
                $resolved = $cur.Resolve()
                if ($resolved -eq $null) { break }
                $cur = $resolved.BaseType
            } catch { break }
            $depth++
        }
    }

    Write-Host ""
    Write-Host "==> All types in MCM.UI namespace (top 20):" -ForegroundColor Cyan
    $asm.MainModule.Types |
        Where-Object { $_.Namespace -like 'MCM.UI*' -and -not $_.IsNested } |
        Sort-Object FullName |
        Select-Object -First 20 |
        ForEach-Object { Write-Host ("  {0}.{1}" -f $_.Namespace, $_.Name) }

    Write-Host ""
    Write-Host "==> Embedded resources:" -ForegroundColor Cyan
    $resources = @($asm.MainModule.Resources)
    Write-Host ("  total: {0}" -f $resources.Count)
    $resources | ForEach-Object { Write-Host ("    {0}" -f $_.Name) }
} finally {
    $asm.Dispose()
}
