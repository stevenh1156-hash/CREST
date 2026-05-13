# Re-deploy the simplified stubs (no DependedModules, no ModulesToLoadAfterThis),
# then rewrite LauncherData.xml so CREST loads at position 1 (before any of the
# stubs and before community mods).

$ErrorActionPreference = 'Stop'

$gameModules  = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules'
$stubsRoot    = 'C:\dev\bannerlord\crest\stubs'
$documents    = [Environment]::GetFolderPath('MyDocuments')
$cfgRoot      = Join-Path $documents 'Mount and Blade II Bannerlord'
$launcherData = Join-Path $cfgRoot 'Configs\LauncherData.xml'

$stubs = @('Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen')

Write-Host "==> Step 1: redeploy simplified stub SubModule.xml files" -ForegroundColor Cyan
foreach ($name in $stubs) {
    $src = Join-Path $stubsRoot "$name\SubModule.xml"
    $dstDir = Join-Path $gameModules $name
    $dst = Join-Path $dstDir 'SubModule.xml'
    if (-not (Test-Path $dstDir)) {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    }
    Copy-Item -Path $src -Destination $dst -Force
    Write-Host "  redeployed $name\SubModule.xml" -ForegroundColor Green
}

Write-Host ""
Write-Host "==> Step 2: rewrite LauncherData.xml so CREST is at position 1" -ForegroundColor Cyan
if (-not (Test-Path $launcherData)) {
    Write-Host "  LauncherData.xml not found, skipping" -ForegroundColor Yellow
    exit 0
}
$backup = "$launcherData.crest-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item -Path $launcherData -Destination $backup
Write-Host "  backup written to: $backup"

[xml]$ld = Get-Content $launcherData

# Re-order: CREST first, then stubs, then everything else preserving original order
$mods = @($ld.UserData.SingleplayerData.ModDatas.UserModData)
$crest = $mods | Where-Object { $_.Id -eq 'CREST' }
$stubMods = @()
foreach ($s in $stubs) {
    $m = $mods | Where-Object { $_.Id -eq $s }
    if ($m) { $stubMods += ,$m }
}
$rest = $mods | Where-Object { $_.Id -ne 'CREST' -and $_.Id -notin $stubs }

# Detach existing children, then re-append in new order
$parent = $ld.UserData.SingleplayerData.ModDatas
foreach ($m in $mods) {
    [void]$parent.RemoveChild($m)
}
if ($crest)    { foreach ($m in @($crest))    { [void]$parent.AppendChild($m) } }
foreach ($m in $stubMods) { [void]$parent.AppendChild($m) }
foreach ($m in $rest)     { [void]$parent.AppendChild($m) }

$ld.Save($launcherData)
Write-Host "  LauncherData.xml rewritten" -ForegroundColor Green

Write-Host ""
Write-Host "==> Step 3: verify new order" -ForegroundColor Cyan
[xml]$ld2 = Get-Content $launcherData
$i = 0
foreach ($m in $ld2.UserData.SingleplayerData.ModDatas.UserModData) {
    $i++
    $on = '[ ]'
    if ($m.IsSelected -eq 'true') { $on = '[X]' }
    if ($i -le 8) { Write-Host ("  {0} {1,3} {2}" -f $on, $i, $m.Id) }
}
Write-Host "  ... (rest unchanged)"

Write-Host ""
Write-Host "==> Done. Launch the game directly (or via launcher with this saved order)." -ForegroundColor Green
