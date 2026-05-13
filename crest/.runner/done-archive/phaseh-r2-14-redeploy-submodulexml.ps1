# Re-render SubModule.xml from the updated template (now includes shim
# DLLs as <Assembly> entries) and redeploy ONLY that file into the live
# CREST module.
$ErrorActionPreference = 'Stop'

$tmplPath = 'C:\dev\bannerlord\crest\Modules\CREST\SubModule.xml.template'
$gameSm   = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\SubModule.xml'

$version = '1.1.0'
$tmpl = Get-Content $tmplPath -Raw
$tmpl = $tmpl -replace '\$version\$', $version
Set-Content -Path $gameSm -Value $tmpl -Encoding UTF8

Write-Host "==> Wrote $gameSm" -ForegroundColor Green
Write-Host ""
Write-Host "==> Verify Assembly entries in deployed file:" -ForegroundColor Cyan
[xml]$x = Get-Content $gameSm
foreach ($sub in $x.Module.SubModules.SubModule) {
    Write-Host ""
    Write-Host ("  [{0}]" -f $sub.Name.value) -ForegroundColor White
    Write-Host ("    DLLName    : {0}" -f $sub.DLLName.value)
    Write-Host ("    ClassType  : {0}" -f $sub.SubModuleClassType.value)
    if ($sub.Assemblies -and $sub.Assemblies.Assembly) {
        $names = @($sub.Assemblies.Assembly | ForEach-Object { $_.value })
        Write-Host ("    Assemblies : {0}" -f ($names -join ', '))
    } else {
        Write-Host "    Assemblies : (none)"
    }
}
