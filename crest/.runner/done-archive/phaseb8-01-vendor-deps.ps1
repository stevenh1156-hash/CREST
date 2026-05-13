$ErrorActionPreference = 'Continue'

# Step 1: copy external third-party DLLs from the working deployed bin into our vendor tree.
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
$vendor = 'C:\dev\bannerlord\crest\vendor\Win64_Shipping_Client'

# These are produced by OUR build - skip them when vendoring (they come from forks).
$builtByUs = @(
    'Crest.Harmony.dll',
    'Crest.ButterLib.dll',
    'Crest.ButterLib.Implementation.dll',
    'Crest.UIExtenderEx.dll',
    'Crest.MCM.dll',
    'Crest.MCM.UI.Adapter.MCMv5.dll',
    'CREST.v1.4.1.dll',
    # Phase H shim outputs (not currently shipped but skip if present)
    'Bannerlord.Harmony.dll',
    'Bannerlord.ButterLib.dll',
    'Bannerlord.UIExtenderEx.dll',
    'MCMv5.dll'
)

# Mono.Cecil + MonoMod.* + 0Harmony come from the Lib.Harmony NuGet package and are
# pulled in transitively when Crest.Harmony builds. They land in Crest.Harmony's
# bin/Release/net472 folder, which Build-CrestBundle's Layer 1 already copies.
# Vendoring these is harmless but redundant; keep them anyway so the bundle works
# even if Crest.Harmony's bin folder is wiped.

if (-not (Test-Path $vendor)) {
    New-Item -ItemType Directory -Path $vendor -Force | Out-Null
}

Write-Host "==> Vendoring third-party deps from $bin -> $vendor" -ForegroundColor Cyan
$copied = 0
$skipped = 0
foreach ($f in (Get-ChildItem $bin -File)) {
    if ($f.Extension -ne '.dll') { continue }
    if ($builtByUs -contains $f.Name) {
        $skipped++
        continue
    }
    Copy-Item $f.FullName -Destination $vendor -Force
    $copied++
}
Write-Host "    copied $copied DLLs, skipped $skipped (built by our forks)"

Write-Host ""
Write-Host "==> Vendor folder contents:" -ForegroundColor Cyan
$total = 0
Get-ChildItem $vendor -File | Sort-Object Name | ForEach-Object {
    Write-Host ("    {0,9:N0}B  {1}" -f $_.Length, $_.Name)
    $total += $_.Length
}
Write-Host ("    TOTAL: {0:N1} MB across $((Get-ChildItem $vendor -File).Count) files" -f ($total/1MB))
