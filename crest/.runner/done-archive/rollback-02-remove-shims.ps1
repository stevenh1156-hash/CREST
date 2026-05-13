$ErrorActionPreference = 'Continue'

# Remove the now-broken shim DLLs from the deployed bin folder.
# They were generated for the Phase H attempt and forward Bannerlord.X.* names
# to Crest.X.dll - but the rolled-back code uses Crest.X.* names so the
# forwarder targets don't exist. Pre-load scanning by Bannerlord's launcher
# of these broken shims is the residual cause of "dependency conflict".
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
$shims = @('Bannerlord.Harmony.dll','Bannerlord.ButterLib.dll','Bannerlord.UIExtenderEx.dll','MCMv5.dll')
Write-Host "==> Removing broken shim DLLs from deployed bin/" -ForegroundColor Cyan
foreach ($n in $shims) {
    $p = Join-Path $bin $n
    if (Test-Path $p) {
        Remove-Item $p -Force
        Write-Host "    removed $n"
    }
}

# Also wipe the staged dist/ shim copies so future bundles don't redeploy them.
# (Build-CrestBundle's [Shims] layer copies from C:\dev\bannerlord\crest\shims\
# which still contains the broken DLLs from the Phase H attempt.)
$shimRoot = 'C:\dev\bannerlord\crest\shims'
if (Test-Path $shimRoot) {
    Write-Host ""
    Write-Host "==> Removing broken shim DLLs from crest\shims\ (so Build-CrestBundle stops copying them)" -ForegroundColor Cyan
    foreach ($n in $shims) {
        $files = Get-ChildItem -Recurse -Path $shimRoot -Filter $n -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            Remove-Item $f.FullName -Force
            Write-Host ("    removed {0}" -f $f.FullName.Substring($shimRoot.Length))
        }
    }
}

# Verify deployed bin folder no longer has shim DLLs
Write-Host ""
Write-Host "==> Final deployed bin folder content:" -ForegroundColor Cyan
$count = (Get-ChildItem $bin -File | Measure-Object).Count
Write-Host "    $count files (was 44, expected 40 after removing 4 shims)"
$shimCount = ($shims | Where-Object { Test-Path (Join-Path $bin $_) } | Measure-Object).Count
Write-Host ("    shim DLLs still present: $shimCount") -ForegroundColor $(if ($shimCount -eq 0) { 'Green' } else { 'Red' })

Write-Host ""
Write-Host "==> v1.0 baseline truly restored - launch the game" -ForegroundColor Green
