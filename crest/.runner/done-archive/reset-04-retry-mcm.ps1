$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Retry MCM build (added using LightInject;)" -ForegroundColor Cyan
$ok = Build-CrestRepo -Name 'MCM'
if (-not $ok) {
    Write-Host "  STILL FAILED" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "==> All forks now built. Running flip-internals-public + shim generator" -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\shims\flip-internals-public.ps1'
& 'C:\dev\bannerlord\crest\shims\generate-shims.ps1'

Write-Host ""
Write-Host "==> Final shim outputs:" -ForegroundColor Cyan
Get-ChildItem -Recurse -Path 'C:\dev\bannerlord\crest\shims' -Filter '*.dll' -ErrorAction SilentlyContinue |
    Sort-Object Name |
    ForEach-Object { Write-Host ("    {0,9:N0}B  {1}" -f $_.Length, (Split-Path $_.FullName -Leaf)) }

Write-Host ""
Write-Host "==> Forwarder counts:" -ForegroundColor Cyan
Add-Type -Path 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'
$shims = @(
    'C:\dev\bannerlord\crest\shims\Bannerlord.Harmony.Shim\Bannerlord.Harmony.dll',
    'C:\dev\bannerlord\crest\shims\Bannerlord.ButterLib.Shim\Bannerlord.ButterLib.dll',
    'C:\dev\bannerlord\crest\shims\Bannerlord.UIExtenderEx.Shim\Bannerlord.UIExtenderEx.dll',
    'C:\dev\bannerlord\crest\shims\MCMv5.Shim\MCMv5.dll'
)
foreach ($s in $shims) {
    if (Test-Path $s) {
        $a = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($s)
        try {
            Write-Host ("    {0,-32}  forwarders={1}" -f (Split-Path $s -Leaf), $a.MainModule.ExportedTypes.Count)
            # Sample first 3 forwarders to verify same-FQN structure
            $a.MainModule.ExportedTypes | Select-Object -First 3 | ForEach-Object {
                Write-Host ("      {0}.{1}  ->  {2}" -f $_.Namespace, $_.Name, $_.Scope.Name)
            }
        } finally { $a.Dispose() }
    }
}
