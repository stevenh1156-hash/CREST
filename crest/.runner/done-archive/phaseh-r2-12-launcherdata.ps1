# Print current LauncherData.xml load order to confirm whether stubs and CREST
# are now in a sensible order for the engine.
$ErrorActionPreference = 'Continue'

$documents    = [Environment]::GetFolderPath('MyDocuments')
$cfgRoot      = Join-Path $documents 'Mount and Blade II Bannerlord'
$launcherData = Join-Path $cfgRoot 'Configs\LauncherData.xml'

if (-not (Test-Path $launcherData)) {
    Write-Host "LauncherData.xml not found at $launcherData" -ForegroundColor Red
    exit 1
}

Write-Host "==> Current LauncherData.xml load order" -ForegroundColor Cyan
[xml]$ld = Get-Content $launcherData
$i = 0
foreach ($m in $ld.UserData.SingleplayerData.ModDatas.UserModData) {
    $i++
    $on = '[ ]'
    if ($m.IsSelected -eq 'true') { $on = '[X]' }
    Write-Host ("  {0} {1,3} {2}" -f $on, $i, $m.Id)
}

Write-Host ""
Write-Host "==> Detect issues" -ForegroundColor Cyan
$enabled = @($ld.UserData.SingleplayerData.ModDatas.UserModData | Where-Object { $_.IsSelected -eq 'true' })
$enabledIds = $enabled | ForEach-Object { $_.Id }

# Find first index of each id (1-based)
function FindIdx($arr, $id) {
    for ($k = 0; $k -lt $arr.Count; $k++) {
        if ($arr[$k] -eq $id) { return $k + 1 }
    }
    return -1
}

$crestIdx = FindIdx $enabledIds 'CREST'
$harmonyIdx = FindIdx $enabledIds 'Bannerlord.Harmony'
$butterlibIdx = FindIdx $enabledIds 'Bannerlord.ButterLib'
$uixIdx = FindIdx $enabledIds 'Bannerlord.UIExtenderEx'
$mcmIdx = FindIdx $enabledIds 'Bannerlord.MBOptionScreen'
$bloodIdx = FindIdx $enabledIds 'BloodMod1313'

Write-Host ("  CREST                  position: {0}" -f $crestIdx)
Write-Host ("  Bannerlord.Harmony     position: {0}" -f $harmonyIdx)
Write-Host ("  Bannerlord.ButterLib   position: {0}" -f $butterlibIdx)
Write-Host ("  Bannerlord.UIExtenderEx position: {0}" -f $uixIdx)
Write-Host ("  Bannerlord.MBOptionScreen position: {0}" -f $mcmIdx)
Write-Host ("  BloodMod1313           position: {0}" -f $bloodIdx)

Write-Host ""
$bad = $false
if ($crestIdx -gt 0 -and $harmonyIdx -gt 0 -and $crestIdx -gt $harmonyIdx) {
    Write-Host "  PROBLEM: Bannerlord.Harmony stub loads BEFORE CREST (stub depends on CREST)" -ForegroundColor Red
    $bad = $true
}
if ($crestIdx -gt 0 -and $butterlibIdx -gt 0 -and $crestIdx -gt $butterlibIdx) {
    Write-Host "  PROBLEM: Bannerlord.ButterLib stub loads BEFORE CREST" -ForegroundColor Red
    $bad = $true
}
if ($crestIdx -gt 0 -and $uixIdx -gt 0 -and $crestIdx -gt $uixIdx) {
    Write-Host "  PROBLEM: Bannerlord.UIExtenderEx stub loads BEFORE CREST" -ForegroundColor Red
    $bad = $true
}
if ($crestIdx -gt 0 -and $mcmIdx -gt 0 -and $crestIdx -gt $mcmIdx) {
    Write-Host "  PROBLEM: Bannerlord.MBOptionScreen stub loads BEFORE CREST" -ForegroundColor Red
    $bad = $true
}
if (-not $bad) {
    Write-Host "  load order is OK" -ForegroundColor Green
}
