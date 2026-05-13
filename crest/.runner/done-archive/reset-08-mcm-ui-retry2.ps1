$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> MCM UI build retry (Bannerlord.Harmony NuGet ref removed)" -ForegroundColor Cyan
$ok = Build-CrestRepo -Name 'MCM'
if (-not $ok) { Write-Error "MCM build failed"; exit 1 }

Write-Host ""
Write-Host "==> Run flip-internals + shim generator" -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\shims\flip-internals-public.ps1'
& 'C:\dev\bannerlord\crest\shims\generate-shims.ps1'

Write-Host ""
Write-Host "==> Final shim outputs:" -ForegroundColor Cyan
Add-Type -Path 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'
foreach ($s in @(
    'C:\dev\bannerlord\crest\shims\Bannerlord.Harmony.Shim\Bannerlord.Harmony.dll',
    'C:\dev\bannerlord\crest\shims\Bannerlord.ButterLib.Shim\Bannerlord.ButterLib.dll',
    'C:\dev\bannerlord\crest\shims\Bannerlord.UIExtenderEx.Shim\Bannerlord.UIExtenderEx.dll',
    'C:\dev\bannerlord\crest\shims\MCMv5.Shim\MCMv5.dll'
)) {
    if (Test-Path $s) {
        $a = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($s)
        try {
            Write-Host ("  {0,9:N0}B  {1}  ({2} forwarders)" -f (Get-Item $s).Length, (Split-Path $s -Leaf), $a.MainModule.ExportedTypes.Count) -ForegroundColor Green
            $a.MainModule.ExportedTypes | Select-Object -First 3 | ForEach-Object {
                Write-Host ("    {0}.{1}  ->  {2}" -f $_.Namespace, $_.Name, $_.Scope.Name)
            }
        } finally { $a.Dispose() }
    }
}
