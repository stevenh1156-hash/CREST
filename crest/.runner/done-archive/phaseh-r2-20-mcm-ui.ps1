# Re-render SubModule.xml with the new MCM UI submodules and verify everything
# the new entries reference is actually present in the deployed bin folder.
$ErrorActionPreference = 'Stop'

$tmpl = Get-Content 'C:\dev\bannerlord\crest\Modules\CREST\SubModule.xml.template' -Raw
$tmpl = $tmpl -replace '\$version\$', '1.1.0'
$dst = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\SubModule.xml'
Set-Content -Path $dst -Value $tmpl -Encoding UTF8

Write-Host "==> Wrote $dst" -ForegroundColor Green

Write-Host ""
Write-Host "==> Verify each SubModule's DLLName + Assembly entries exist:" -ForegroundColor Cyan
[xml]$x = Get-Content $dst
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
$problems = 0
foreach ($sub in $x.Module.SubModules.SubModule) {
    Write-Host ""
    Write-Host ("  [{0}]" -f $sub.Name.value) -ForegroundColor White
    $dll = $sub.DLLName.value
    $dllPath = Join-Path $bin $dll
    if (Test-Path $dllPath) {
        Write-Host ("    DLLName    : {0}  OK" -f $dll) -ForegroundColor Green
    } else {
        Write-Host ("    DLLName    : {0}  MISSING" -f $dll) -ForegroundColor Red
        $problems++
    }
    Write-Host ("    ClassType  : {0}" -f $sub.SubModuleClassType.value)
    if ($sub.Assemblies -and $sub.Assemblies.Assembly) {
        foreach ($asm in @($sub.Assemblies.Assembly)) {
            $name = $asm.value
            $p = Join-Path $bin $name
            if (Test-Path $p) {
                Write-Host ("    Assembly   : {0}  OK" -f $name) -ForegroundColor Green
            } else {
                Write-Host ("    Assembly   : {0}  MISSING" -f $name) -ForegroundColor Red
                $problems++
            }
        }
    }
}

Write-Host ""
if ($problems -eq 0) {
    Write-Host "==> All references resolve. Try launching the game." -ForegroundColor Green
} else {
    Write-Host ("==> {0} unresolved references. Bundle is broken." -f $problems) -ForegroundColor Red
    exit 1
}
