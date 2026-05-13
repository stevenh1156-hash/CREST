$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Phase J retry: namespace fixed" -ForegroundColor Cyan
$ok = Build-CrestRepo -Name 'Harmony'
if (-not $ok) { exit 1 }

Write-Host ""
Write-Host "==> Re-bundle + deploy" -ForegroundColor Cyan
$ok = Build-CrestBundle -SkipBuild -Version '1.0.0'
if (-not $ok) { exit 2 }
$ok = Deploy-CrestToBannerlord
if (-not $ok) { exit 3 }

# Verify Crest.Harmony.dll has the CrestQuickStart class
Add-Type -Path 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'
$dll = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client\Crest.Harmony.dll'
$a = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dll)
try {
    $found = $a.MainModule.Types | Where-Object { $_.Name -eq 'CrestQuickStart' } | Select-Object -First 1
    if ($found) {
        Write-Host ""
        Write-Host ("==> Verified: CrestQuickStart in deployed Crest.Harmony.dll  ({0}.{1})" -f $found.Namespace, $found.Name) -ForegroundColor Green
    } else {
        Write-Host "==> WARNING: CrestQuickStart class not found in deployed DLL" -ForegroundColor Red
    }
} finally { $a.Dispose() }

Write-Host ""
Write-Host "==> Launch the game - intro video should now skip" -ForegroundColor Green
