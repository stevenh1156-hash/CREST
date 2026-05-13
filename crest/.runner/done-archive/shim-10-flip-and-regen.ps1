$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

# Step 1: dry-run the flip-internals-public to see counts before writing
Write-Host "==> Dry-run flip-internals-public on all 4 forks (before)" -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\shims\flip-internals-public.ps1' -DryRun

# Step 2: actually rewrite each Crest.X.dll in-place
Write-Host ""
Write-Host "==> Rewriting (in-place, ReadWrite mode)" -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\shims\flip-internals-public.ps1'

# Step 3: re-run shim generator now that public surface is wider
Write-Host ""
Write-Host "==> Regenerating shims with widened public surface" -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\shims\generate-shims.ps1'

# Step 4: list all shim DLLs
Write-Host ""
Write-Host "==> Final shim outputs:" -ForegroundColor Cyan
Get-ChildItem -Recurse 'C:\dev\bannerlord\crest\shims' -Filter '*.dll' -ErrorAction SilentlyContinue |
    Sort-Object Name |
    ForEach-Object { Write-Host ("    {0,9:N0}B  {1}" -f $_.Length, $_.FullName) }

# Step 5: also run a quick sanity check - load each shim and count exported types
Write-Host ""
Write-Host "==> Forwarder counts per shim:" -ForegroundColor Cyan
Add-Type -Path 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'
$shims = @(
    'C:\dev\bannerlord\crest\shims\Bannerlord.Harmony.Shim\Bannerlord.Harmony.dll',
    'C:\dev\bannerlord\crest\shims\Bannerlord.ButterLib.Shim\Bannerlord.ButterLib.dll',
    'C:\dev\bannerlord\crest\shims\Bannerlord.UIExtenderEx.Shim\Bannerlord.UIExtenderEx.dll',
    'C:\dev\bannerlord\crest\shims\MCMv5.Shim\MCMv5.dll'
)
foreach ($s in $shims) {
    if (-not (Test-Path $s)) { continue }
    $a = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($s)
    try {
        Write-Host ("    {0,-30}  forwarders={1}" -f (Split-Path $s -Leaf), $a.MainModule.ExportedTypes.Count)
    } finally { $a.Dispose() }
}
