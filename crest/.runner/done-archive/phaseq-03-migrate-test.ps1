$ErrorActionPreference = 'Continue'

Write-Host '==> Test 1: dry-run on BloodMod1313 (should detect MCMv5 reference)' -ForegroundColor Cyan
$bloodMod = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\BloodMod1313'
& 'C:\dev\bannerlord\crest\tools\migrate\Migrate-ModToCrest.ps1' -Path $bloodMod -DryRun

Write-Host ''
Write-Host '==> Test 2: dry-run sweep across community mods to map coverage' -ForegroundColor Cyan
$gameModules = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules'
$mods = @(
    'BloodMod1313','IDontCare','DismembermentPlus','Bannerlord.FluidCombatLite','DynaCulture',
    'FasterTime','CompanionHotswap','BanditBlackHole','ImmersiveBattlefields','PerfectFireArrows',
    'RaiseYourBanner','RaiseYourTorch','AutoEquipCompanions','ImprovedGarrisons','CharacterReload',
    'BannerFixPerformance','CargoHolds','LifelongLearning','BirthAndDeath','RTSCamera','RTSCamera.CommandSystem'
)
foreach ($m in $mods) {
    $p = Join-Path $gameModules $m
    if (-not (Test-Path $p)) { continue }
    Write-Host ''
    Write-Host ('---- ' + $m + ' ----') -ForegroundColor White
    & 'C:\dev\bannerlord\crest\tools\migrate\Migrate-ModToCrest.ps1' -Path $p -DryRun
}
