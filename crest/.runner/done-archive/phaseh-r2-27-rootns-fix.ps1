$ErrorActionPreference = 'Stop'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Build MCM (RootNamespace fix means a full rebuild of MCM.UI)" -ForegroundColor Cyan
$ok = Build-CrestRepo -Name 'MCM' -Clean
if (-not $ok) { exit 1 }

Write-Host ""
Write-Host "==> Reassemble bundle (rebuilds bin folder including shims, vendored deps)" -ForegroundColor Cyan
$ok = Build-CrestBundle -Version '1.1.0' -SkipBuild
if (-not $ok) { exit 2 }

Write-Host ""
Write-Host "==> Deploy" -ForegroundColor Cyan
$ok = Deploy-CrestToBannerlord
if (-not $ok) { exit 3 }

Write-Host ""
Write-Host "==> Re-render full SubModule.xml from template" -ForegroundColor Cyan
$tmpl = Get-Content 'C:\dev\bannerlord\crest\Modules\CREST\SubModule.xml.template' -Raw
$tmpl = $tmpl -replace '\$version\$', '1.1.0'
$dst = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\SubModule.xml'
Set-Content -Path $dst -Value $tmpl -Encoding UTF8

Write-Host ""
Write-Host "==> Verify embedded resource names in the freshly-built CREST.v1.4.1.dll" -ForegroundColor Cyan
$cecilPath = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'
Add-Type -Path $cecilPath
$dll = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client\CREST.v1.4.1.dll'
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dll)
try {
    $crestPrefix = 0
    $mcmPrefix = 0
    foreach ($r in $asm.MainModule.Resources) {
        if ($r.Name -like 'Crest.MCM.UI.*') { $crestPrefix++ }
        elseif ($r.Name -like 'MCM.UI.*')   { $mcmPrefix++ }
    }
    Write-Host ("  resources prefixed Crest.MCM.UI.* : {0}" -f $crestPrefix)
    Write-Host ("  resources prefixed MCM.UI.*       : {0}" -f $mcmPrefix)
    if ($mcmPrefix -gt 0 -and $crestPrefix -eq 0) {
        Write-Host "  RootNamespace fix confirmed." -ForegroundColor Green
    } else {
        Write-Host "  RootNamespace fix NOT applied correctly." -ForegroundColor Red
        exit 4
    }
} finally { $asm.Dispose() }

Write-Host ""
Write-Host "==> Done. Launch and try Mod Options." -ForegroundColor Green
