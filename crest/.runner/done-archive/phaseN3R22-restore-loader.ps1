$ErrorActionPreference = 'Continue'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$installBin = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'

# Restore Bannerlord.ModuleLoader.CREST.dll from build output (since SubModule.xml requires it)
$src = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI\bin\Stable_Release\netstandard2.0\Bannerlord.ModuleLoader.CREST.dll'
$dst = Join-Path $installBin 'Bannerlord.ModuleLoader.CREST.dll'
if (Test-Path $src) {
    Copy-Item $src $dst -Force
    Write-Host ('   restored ' + $dst + '  (' + ([math]::Round((Get-Item $dst).Length/1KB)) + ' KB)') -ForegroundColor Green
} else { Write-Host '   src missing!' -ForegroundColor Red }

# Now check if there are TWO CREST.v1.4.1.dll-equivalents — one inside the
# loader and one standalone. ModuleLoader probably embeds version-specific
# DLLs as resources. If both are present we'd get duplicate-load.
Write-Host ''
Write-Host '==> Cecil-inspect Bannerlord.ModuleLoader.CREST.dll for embedded resources' -ForegroundColor Cyan
$cecilDll = Join-Path $installBin 'Mono.Cecil.dll'
[Reflection.Assembly]::LoadFrom($cecilDll) | Out-Null
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dst)
foreach ($r in $asm.MainModule.Resources) {
    Write-Host ('   resource: ' + $r.Name)
}
$asm.Dispose()

Write-Host ''
Write-Host '==> ALSO check: do we have BOTH CREST.v1.4.1.dll AND a version embedded inside ModuleLoader?' -ForegroundColor Cyan
$verDll = Join-Path $installBin 'CREST.v1.4.1.dll'
if (Test-Path $verDll) { Write-Host ('   CREST.v1.4.1.dll IS present standalone — possible double-load') -ForegroundColor Yellow }
