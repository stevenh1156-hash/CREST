$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host '==> Build Harmony (CrestMessageStyle + crest.json default change) and MCM (CrestSettings toggle)' -ForegroundColor Cyan
$ok1 = Build-CrestRepo -Name 'Harmony'
$ok2 = Build-CrestRepo -Name 'MCM'
if (-not ($ok1 -and $ok2)) { exit 1 }

Write-Host ''
Write-Host '==> Re-flip + regen shims (Harmony rebuild touched Crest.Harmony.dll)' -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\shims\flip-internals-public.ps1'
& 'C:\dev\bannerlord\crest\shims\generate-shims.ps1'

Write-Host ''
Write-Host '==> Reassemble bundle + redeploy' -ForegroundColor Cyan
$ok = Build-CrestFullBundle -Version '1.3.0' -SkipBuild
if (-not $ok) { exit 2 }
$ok = Deploy-CrestFullToBannerlord
if (-not $ok) { exit 3 }

Write-Host ''
Write-Host '==> Verify CrestMessageStyle is in deployed Crest.Harmony.dll' -ForegroundColor Cyan
$cecilPath = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'
Add-Type -Path $cecilPath
$dll = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client\Crest.Harmony.dll'
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dll)
try {
    $found = $false
    foreach ($t in $asm.MainModule.Types) {
        if ($t.Name -eq 'CrestMessageStyle') {
            $found = $true
            Write-Host ('  OK   ' + $t.Namespace + '.' + $t.Name) -ForegroundColor Green
            break
        }
    }
    if (-not $found) { Write-Host '  MISSING CrestMessageStyle' -ForegroundColor Red }
} finally { $asm.Dispose() }

Write-Host ''
Write-Host '==> Verify CrestSettings has new MainMenuMonotone property' -ForegroundColor Cyan
$dll2 = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client\CREST.v1.4.1.dll'
$asm2 = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dll2)
try {
    foreach ($t in $asm2.MainModule.Types) {
        if ($t.Name -eq 'CrestSettings') {
            $names = @($t.Properties | Where-Object { $_.PropertyType.FullName -eq 'System.Boolean' } | ForEach-Object { $_.Name })
            Write-Host ('  bool props: ' + ($names -join ', '))
            if ($names -contains 'MainMenuMonotone') {
                Write-Host '  OK MainMenuMonotone present' -ForegroundColor Green
            } else {
                Write-Host '  MISSING MainMenuMonotone' -ForegroundColor Red
            }
            break
        }
    }
} finally { $asm2.Dispose() }

Write-Host ''
Write-Host '==> Repackage zip' -ForegroundColor Cyan
$zip = New-CrestFullZip -Version '1.3.0'
if ($zip) { Write-Host ('  zip: ' + $zip) -ForegroundColor Green }

Write-Host ''
Write-Host '==> Done. Launch via Steam, mod-load messages should now be a single off-white color.' -ForegroundColor Green
