# Diagnose dependency conflict (retry without inline if-expressions).
$ErrorActionPreference = 'Continue'

$gameModules = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules'
$documents   = [Environment]::GetFolderPath('MyDocuments')
$cfgRoot     = Join-Path $documents 'Mount and Blade II Bannerlord'

Write-Host "==> LauncherData.xml: enabled mods + load order" -ForegroundColor Cyan
$launcherData = Join-Path $cfgRoot 'Configs\LauncherData.xml'
if (Test-Path $launcherData) {
    [xml]$ld = Get-Content $launcherData
    $node = $ld.UserData
    if ($node -and $node.SingleplayerData -and $node.SingleplayerData.ModDatas -and $node.SingleplayerData.ModDatas.UserModData) {
        $i = 0
        foreach ($m in $node.SingleplayerData.ModDatas.UserModData) {
            $i++
            $on = '[ ]'
            if ($m.IsSelected -eq 'true') { $on = '[X]' }
            Write-Host ("  {0} {1,3} {2}" -f $on, $i, $m.Id)
        }
    } else {
        Write-Host "  (no UserModData found)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  not found at $launcherData" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==> Stub-vs-installed-modules cross-check" -ForegroundColor Cyan
$stubs = @('Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen')
foreach ($s in $stubs) {
    $sm = Join-Path $gameModules "$s\SubModule.xml"
    if (-not (Test-Path $sm)) {
        Write-Host "  $s : MISSING SubModule.xml" -ForegroundColor Red
        continue
    }
    [xml]$x = Get-Content $sm
    $deps = @()
    if ($x.Module.DependedModules) {
        foreach ($d in $x.Module.DependedModules.DependedModule) {
            if ($d.Id) { $deps += $d.Id }
        }
    }
    Write-Host ("  {0}  deps: {1}" -f $s, ($deps -join ', '))
    foreach ($d in $deps) {
        $depDir = Join-Path $gameModules $d
        if (Test-Path $depDir) {
            Write-Host "    $d : OK" -ForegroundColor Green
        } else {
            Write-Host "    $d : NOT INSTALLED" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "==> BloodMod1313 SubModule.xml DependedModules check" -ForegroundColor Cyan
$bm = Join-Path $gameModules 'BloodMod1313\SubModule.xml'
if (Test-Path $bm) {
    [xml]$x = Get-Content $bm
    foreach ($d in $x.Module.DependedModules.DependedModule) {
        $id = $d.Id
        if (-not $id) { continue }
        $depDir = Join-Path $gameModules $id
        $present = Test-Path $depDir
        $status = 'MISSING'
        $color = 'Red'
        if ($present) { $status = 'OK'; $color = 'Green' }
        Write-Host ("  {0,-30} {1}" -f $id, $status) -ForegroundColor $color
    }
}

Write-Host ""
Write-Host "==> Recent crash logs / runtime.log" -ForegroundColor Cyan
$paths = @(
    'C:\dev\bannerlord\crest\runtime.log',
    (Join-Path $cfgRoot 'CrashLogs')
)
foreach ($p in $paths) {
    if (Test-Path $p) {
        if ((Get-Item $p).PSIsContainer) {
            Write-Host "  $p :" -ForegroundColor Cyan
            Get-ChildItem $p -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 3 |
                ForEach-Object { Write-Host ("    {0}  {1,8:N0} bytes" -f $_.LastWriteTime, $_.Length) }
        } else {
            Write-Host ""
            Write-Host "  $p (last 60 lines):" -ForegroundColor Cyan
            Get-Content $p -Tail 60 | ForEach-Object { Write-Host "    $_" }
        }
    } else {
        Write-Host "  not found: $p" -ForegroundColor DarkGray
    }
}
