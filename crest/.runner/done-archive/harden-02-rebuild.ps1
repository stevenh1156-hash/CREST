Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Rebuilding Crest.ButterLib with hardened ImplementationLoader..." -ForegroundColor Cyan
$ok = Build-CrestRepo -Name ButterLib -Clean
if (-not $ok) { Write-Host "==> Build failed" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "==> Rebuilding bundle (no version checks anywhere)..." -ForegroundColor Cyan
$built = Build-CrestBundle -SkipBuild
if (-not $built) { exit 1 }

Write-Host ""
Write-Host "==> Verifying SubModule.xml class refs..." -ForegroundColor Cyan
$bin = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client'
Add-Type -Path (Join-Path $bin 'Mono.Cecil.dll')
$xml = [xml](Get-Content 'C:\dev\bannerlord\crest\dist\CREST\SubModule.xml' -Raw)
$allOk = $true
foreach ($s in $xml.Module.SubModules.SubModule) {
    $name = $s.Name.value; $dll = $s.DLLName.value; $cls = $s.SubModuleClassType.value
    $p = Join-Path $bin $dll
    $found = $false
    if (Test-Path $p) {
        try {
            $asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($p)
            foreach ($mod in $asm.Modules) { foreach ($t in $mod.Types) { if ($t.FullName -eq $cls) { $found = $true } } }
            $asm.Dispose()
        } catch {}
    }
    $color = if ($found) { 'Green' } else { 'Red' }
    Write-Host ("    [{0}] {1,-32} {2} :: {3}" -f $(if ($found) {'OK '} else {'MISS'}), $name, $dll, $cls) -ForegroundColor $color
    if (-not $found) { $allOk = $false }
}

if ($allOk) {
    Deploy-CrestToBannerlord | Out-Null
    Write-Host ""
    Write-Host "==> Hardened bundle redeployed. Try launching." -ForegroundColor Green
} else {
    exit 1
}
