# Re-render SubModule.xml from updated template (now references the
# implementation SubModule class directly instead of the dynamic loader).
$ErrorActionPreference = 'Stop'

$tmpl = Get-Content 'C:\dev\bannerlord\crest\Modules\CREST\SubModule.xml.template' -Raw
$tmpl = $tmpl -replace '\$version\$', '1.1.0'
$dst = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\SubModule.xml'
Set-Content -Path $dst -Value $tmpl -Encoding UTF8

Write-Host "==> Wrote $dst" -ForegroundColor Green
Write-Host ""
Write-Host "==> Verify each SubModule entry:" -ForegroundColor Cyan
[xml]$x = Get-Content $dst
foreach ($sub in $x.Module.SubModules.SubModule) {
    Write-Host ""
    Write-Host ("  [{0}]" -f $sub.Name.value)
    Write-Host ("    DLLName    : {0}" -f $sub.DLLName.value)
    Write-Host ("    ClassType  : {0}" -f $sub.SubModuleClassType.value)
    if ($sub.Assemblies -and $sub.Assemblies.Assembly) {
        $names = @($sub.Assemblies.Assembly | ForEach-Object { $_.value })
        Write-Host ("    Assemblies : {0}" -f ($names -join ', '))
    }
}
