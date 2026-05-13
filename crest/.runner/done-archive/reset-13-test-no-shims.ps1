$ErrorActionPreference = 'Continue'

# Move the shim DLLs out of bin/ to a sibling folder so the launcher doesn't see them.
# This isolates whether the shims are causing the dependency conflict.
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
$staging = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\shims-disabled'
New-Item -ItemType Directory -Path $staging -Force | Out-Null

$shims = @('Bannerlord.Harmony.dll','Bannerlord.ButterLib.dll','Bannerlord.UIExtenderEx.dll','MCMv5.dll')
Write-Host "==> Moving shim DLLs out of bin/ for isolation test" -ForegroundColor Cyan
foreach ($n in $shims) {
    $src = Join-Path $bin $n
    if (Test-Path $src) {
        Move-Item $src -Destination (Join-Path $staging $n) -Force
        Write-Host ("    moved {0}" -f $n)
    }
}
Write-Host ""
Write-Host "==> bin/ now has no shims. Launch the game to see if the dependency-conflict dialog still appears." -ForegroundColor Green
Write-Host "    If clean: shims need a different staging strategy (sub-folder + AppDomain resolve handler)."
Write-Host "    If still error: shims are not the cause; problem is elsewhere."
