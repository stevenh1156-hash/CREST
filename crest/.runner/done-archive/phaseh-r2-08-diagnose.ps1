# Diagnose the "dependency conflict" error for BloodMod1313 / Blood Bath.
# Gathers: LauncherData.xml (enabled mods + load order), runtime.log,
# game crash log if present, and validates each stub's referenced
# DependedModule actually exists in Modules\.

$ErrorActionPreference = 'Continue'

$gameModules = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules'
$documents   = [Environment]::GetFolderPath('MyDocuments')
$cfgRoot     = Join-Path $documents 'Mount and Blade II Bannerlord'

Write-Host "==> LauncherData.xml — enabled mods + load order" -ForegroundColor Cyan
$launcherData = Join-Path $cfgRoot 'Configs\LauncherData.xml'
if (Test-Path $launcherData) {
    [xml]$ld = Get-Content $launcherData
    $node = $ld.UserData
    if ($node -and $node.SingleplayerData -and $node.SingleplayerData.ModDatas -and $node.SingleplayerData.ModDatas.UserModData) {
        $i = 0
        foreach ($m in $node.SingleplayerData.ModDatas.UserModData) {
            $i++
            $on = if ($m.IsSelected -eq 'true') { 'X' } else { ' ' }
            Write-Host ("  [{0}] {1,3} {2}" -f $on, $i, $m.Id)
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
            Write-Host "    $d : OK"
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
        $color = if ($present) { 'Green' } else { 'Red' }
        Write-Host ("  {0,-30} {1}" -f $id, (if ($present) {'OK'} else {'MISSING'})) -ForegroundColor $color
    }
}

Write-Host ""
Write-Host "==> Recent runtime.log (last 80 lines)" -ForegroundColor Cyan
$runtimeLog = Join-Path 'C:\dev\bannerlord\crest' 'runtime.log'
if (Test-Path $runtimeLog) {
    Get-Content $runtimeLog -Tail 80 | ForEach-Object { Write-Host "    $_" }
} else {
    Write-Host "  (no runtime.log at $runtimeLog)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==> Game crash log root contents" -ForegroundColor Cyan
$crashRoot = Join-Path $cfgRoot 'CrashLogs'
if (Test-Path $crashRoot) {
    Get-ChildItem $crashRoot -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 5 |
        ForEach-Object { Write-Host ("  {0}  {1}" -f $_.LastWriteTime, $_.FullName) }
} else {
    Write-Host "  (none)" -ForegroundColor DarkGray
}
