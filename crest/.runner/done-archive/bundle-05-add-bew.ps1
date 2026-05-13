Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Re-assembling bundle with BetterExceptionWindow included..." -ForegroundColor Cyan
$ok = Build-CrestBundle -SkipBuild
if (-not $ok) { exit 1 }

Write-Host ""
Write-Host "==> Verifying SubModule entries..." -ForegroundColor Cyan
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
    if (Test-Path $dllPath) {
        try {
            $asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dllPath)
            foreach ($mod in $asm.Modules) {
                foreach ($t in $mod.Types) {
                    if ($t.FullName -eq $classFqn) { $found = $true }
                }
            }
            $asm.Dispose()
        } catch {
            Write-Host "    [$name] error: $_" -ForegroundColor Red
        }
    }
    if ($found) {
        Write-Host ("    [{0,-32}] OK    {1}::{2}" -f $name, $dll, $classFqn) -ForegroundColor Green
    } else {
        Write-Host ("    [{0,-32}] MISS  {1}::{2}" -f $name, $dll, $classFqn) -ForegroundColor Red
        $allOk = $false
    }
}

# Audit Assembly references too
Write-Host ""
Write-Host "==> Verifying <Assembly> references resolve to files in bin\:" -ForegroundColor Cyan
foreach ($s in $xml.Module.SubModules.SubModule) {
    foreach ($a in $s.Assemblies.Assembly) {
        if ($a.value) {
            $p = Join-Path $bin $a.value
            if (Test-Path $p) {
                Write-Host ("    OK   {0}" -f $a.value) -ForegroundColor Green
            } else {
                Write-Host ("    MISS {0}" -f $a.value) -ForegroundColor Red
                $allOk = $false
            }
        }
    }
}

# Show full bundle layout including assets
Write-Host ""
Write-Host "==> Bundle root:" -ForegroundColor Cyan
$staging = 'C:\dev\bannerlord\crest\dist\CREST'
Get-ChildItem $staging -File | Sort-Object Name | ForEach-Object {
    Write-Host ("    {0,9:N1}KB  {1}" -f ($_.Length/1KB), $_.Name)
}
$mddir = Join-Path $staging 'ModuleData'
if (Test-Path $mddir) {
    Write-Host ""
    Write-Host "==> ModuleData tree:" -ForegroundColor Cyan
    Get-ChildItem $mddir -Recurse -File | ForEach-Object {
        Write-Host ("    {0,9:N1}KB  ModuleData\{1}" -f ($_.Length/1KB), $_.FullName.Replace($mddir + '\','').Replace('\','/'))
    }
}

if ($allOk) {
    Write-Host ""
    Write-Host "==> Deploying..." -ForegroundColor Cyan
    Deploy-CrestToBannerlord | Out-Null
    Write-Host "==> Bundle redeployed with BEW included" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next: launch Bannerlord. Tick CREST + Native + SandBoxCore + Sandbox + StoryMode + CustomBattle."
    Write-Host "      Leave Bannerlord.Harmony, ButterLib, UIExtenderEx, MBOptionScreen, BetterExceptionWindow UNTICKED."
    Write-Host "      (BEW now lives inside CREST so the standalone one doesn't need to be enabled.)"
} else {
    Write-Host "==> Bundle has unresolved references; not deploying." -ForegroundColor Red
}
exit 0
