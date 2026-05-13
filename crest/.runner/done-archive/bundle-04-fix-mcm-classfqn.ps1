Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Re-assembling bundle with fixed MCM class FQN..." -ForegroundColor Cyan
$ok = Build-CrestBundle -SkipBuild
if (-not $ok) { exit 1 }

Write-Host ""
Write-Host "==> Verifying SubModule.xml entries map to actual classes in their DLLs..." -ForegroundColor Cyan
$bin = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client'
Add-Type -Path (Join-Path $bin 'Mono.Cecil.dll')

$xml = [xml](Get-Content 'C:\dev\bannerlord\crest\dist\CREST\SubModule.xml' -Raw)
$allOk = $true
foreach ($s in $xml.Module.SubModules.SubModule) {
    $name = $s.Name.value
    $dll = $s.DLLName.value
    $classFqn = $s.SubModuleClassType.value
    $dllPath = Join-Path $bin $dll
    $found = $false
    try {
        $asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dllPath)
        foreach ($mod in $asm.Modules) {
            foreach ($t in $mod.Types) {
                if ($t.FullName -eq $classFqn) { $found = $true }
            }
        }
        $asm.Dispose()
    } catch {
        Write-Host "    [$name] error reading ${dll}: $_" -ForegroundColor Red
    }
    if ($found) {
        Write-Host ("    [{0,-22}] {1}::{2}  OK" -f $name, $dll, $classFqn) -ForegroundColor Green
    } else {
        Write-Host ("    [{0,-22}] {1}::{2}  CLASS NOT FOUND" -f $name, $dll, $classFqn) -ForegroundColor Red
        $allOk = $false
    }
}

if ($allOk) {
    Write-Host ""
    Write-Host "==> All SubModule entries verified. Redeploying..." -ForegroundColor Green
    Deploy-CrestToBannerlord | Out-Null

    Write-Host ""
    Write-Host "==> Repackaging zip..." -ForegroundColor Cyan
    New-CrestZip | Out-Null

    Write-Host ""
    Write-Host "==> READY TO RELAUNCH BANNERLORD" -ForegroundColor Green
    Write-Host "    The MCM class-resolution fix should let the game boot past CREST init."
    Write-Host "    Tip: tick BetterExceptionWindow in the launcher to capture any further crash."
} else {
    Write-Host ""
    Write-Host "==> SubModule.xml has unresolved class references. NOT redeploying." -ForegroundColor Red
    exit 1
}
exit 0
