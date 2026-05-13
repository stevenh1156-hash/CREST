Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Rebuilding Crest.ButterLib with hardened ImplementationLoader (no version checks)..." -ForegroundColor Cyan
$ok = Build-CrestRepo -Name ButterLib -Clean
if (-not $ok) {
    Write-Host "==> Build failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "==> Sanity-check: ImplementationLoader source no longer globs version-suffixed files:" -ForegroundColor Cyan
$src = 'C:\dev\bannerlord\Bannerlord.ButterLib\src\Crest.ButterLib\ImplementationLoaderSubModule.cs'
$hits = Select-String -Path $src -Pattern 'Implementation\.\*\.dll|GameVersion|gameVersion' -ErrorAction SilentlyContinue
Write-Host "    matching lines (should be 0 or comment-only):"
$hits | ForEach-Object { Write-Host "      L$($_.LineNumber)  $($_.Line.Trim())" }

Write-Host ""
Write-Host "==> Rebuilding bundle with simplified SubModule.xml (no version constraints, bypass MCM loader)..." -ForegroundColor Cyan
$built = Build-CrestBundle -SkipBuild
if (-not $built) { exit 1 }

Write-Host ""
Write-Host "==> Verifying SubModule.xml entries map to real classes..." -ForegroundColor Cyan
$bin = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client'
Add-Type -Path (Join-Path $bin 'Mono.Cecil.dll')
$xml = [xml](Get-Content 'C:\dev\bannerlord\crest\dist\CREST\SubModule.xml' -Raw)
$ok = $true
foreach ($s in $xml.Module.SubModules.SubModule) {
    $name = $s.Name.value
    $dll = $s.DLLName.value
    $cls = $s.SubModuleClassType.value
    $p = Join-Path $bin $dll
    $found = $false
    if (Test-Path $p) {
        try {
            $asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($p)
            foreach ($mod in $asm.Modules) {
                foreach ($t in $mod.Types) { if ($t.FullName -eq $cls) { $found = $true } }
            }
            $asm.Dispose()
        } catch {}
    }
    $tag = if ($found) { 'OK ' } else { 'MISS' }
    $col = if ($found) { 'Green' } else { 'Red' }
    Write-Host ("    [$tag] {0,-32} {1} :: {2}" -f $name, $dll, $cls) -ForegroundColor $col
    if (-not $found) { $ok = $false }
}

if ($ok) {
    Write-Host ""
    Write-Host "==> Redeploying full bundle..." -ForegroundColor Cyan
    Deploy-CrestToBannerlord | Out-Null
    Write-Host "==> Done. Try launching with full CREST + Native ticked." -ForegroundColor Green
} else {
    Write-Host "==> Verification failed; not deploying." -ForegroundColor Red
}
exit 0
