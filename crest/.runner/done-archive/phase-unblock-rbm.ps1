$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host '==> Build Harmony (CrestUnblock + AutoUnblock default)' -ForegroundColor Cyan
$ok = Build-CrestRepo -Name 'Harmony'
if (-not $ok) { exit 1 }

& 'C:\dev\bannerlord\crest\shims\flip-internals-public.ps1'
& 'C:\dev\bannerlord\crest\shims\generate-shims.ps1'

Write-Host ''
Write-Host '==> Reassemble + redeploy' -ForegroundColor Cyan
$ok = Build-CrestFullBundle -Version '1.4.0' -SkipBuild
if (-not $ok) { exit 2 }
$ok = Deploy-CrestFullToBannerlord
if (-not $ok) { exit 3 }

Write-Host ''
Write-Host '==> Verify CrestUnblock is in deployed Crest.Harmony.dll' -ForegroundColor Cyan
$cecilPath = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'
Add-Type -Path $cecilPath
$dll = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client\Crest.Harmony.dll'
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dll)
try {
    $hasUnblock = $false
    foreach ($t in $asm.MainModule.Types) {
        if ($t.Name -eq 'CrestUnblock') { $hasUnblock = $true; break }
    }
    if ($hasUnblock) {
        Write-Host '  OK   Bannerlord.Harmony.CrestUnblock' -ForegroundColor Green
    } else {
        Write-Host '  MISS CrestUnblock' -ForegroundColor Red
    }
} finally { $asm.Dispose() }

Write-Host ''
Write-Host '==> Confirm Unblock-CrestInstall.ps1 is shipped in Modules\CREST\' -ForegroundColor Cyan
$installer = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\Unblock-CrestInstall.ps1'
if (Test-Path $installer) {
    $f = Get-Item $installer
    Write-Host ('  OK   ' + $f.Length + 'B  ' + $f.Name) -ForegroundColor Green
} else {
    Write-Host '  MISS Unblock-CrestInstall.ps1' -ForegroundColor Red
}

Write-Host ''
Write-Host '==> Crest-Doctor on RBM' -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\tools\doctor\Crest-Doctor.ps1' -Mod 'RBM'

Write-Host ''
Write-Host '==> Crest-Doctor on RBM_WS' -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\tools\doctor\Crest-Doctor.ps1' -Mod 'RBM_WS'

Write-Host ''
Write-Host '==> Migrate-ModToCrest dry-run on RBM' -ForegroundColor Cyan
$rbm = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\RBM'
& 'C:\dev\bannerlord\crest\tools\migrate\Migrate-ModToCrest.ps1' -Path $rbm -DryRun

Write-Host ''
Write-Host '==> Migrate-ModToCrest dry-run on RBM_WS' -ForegroundColor Cyan
$rbmws = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\RBM_WS'
& 'C:\dev\bannerlord\crest\tools\migrate\Migrate-ModToCrest.ps1' -Path $rbmws -DryRun
