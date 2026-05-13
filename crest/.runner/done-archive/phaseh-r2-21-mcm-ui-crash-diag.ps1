# Capture diagnostic data for the MCM UI crash. The MCM-UI submodules were
# just added; the game is now crashing at loading screen.
#
# Pull: latest ModLogs (after the crash), runtime.log tail, BEW error.htm
# if it dropped one, and check what FQN MCM UI is trying to harmony-patch.

$ErrorActionPreference = 'Continue'

$documents = [Environment]::GetFolderPath('MyDocuments')
$cfgRoot   = Join-Path $documents 'Mount and Blade II Bannerlord'

Write-Host "==> ModLogs (newest, last 200 lines)" -ForegroundColor Cyan
$latest = Get-ChildItem (Join-Path $cfgRoot 'Configs\ModLogs') -Filter 'default*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latest) {
    Write-Host ("  reading: {0}  modified {1}" -f $latest.FullName, $latest.LastWriteTime)
    Get-Content $latest.FullName -Tail 200 | ForEach-Object { Write-Host "    $_" }
}

Write-Host ""
Write-Host "==> runtime.log: tail (last 80 lines)" -ForegroundColor Cyan
$rl = 'C:\dev\bannerlord\crest\runtime.log'
if (Test-Path $rl) {
    $f = Get-Item $rl
    Write-Host ("  size: {0:N0}B  modified: {1}" -f $f.Length, $f.LastWriteTime)
    Get-Content $rl -Tail 80 | ForEach-Object { Write-Host "    $_" }
}

Write-Host ""
Write-Host "==> BEW dropped error reports" -ForegroundColor Cyan
$crestRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'
foreach ($pattern in @('*.htm','*.html','crashreport*','error*')) {
    Get-ChildItem $crestRoot -Filter $pattern -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-30) } |
        ForEach-Object { Write-Host ("  {0,8:N0}B  {1}  {2}" -f $_.Length, $_.LastWriteTime, $_.FullName) }
}

Write-Host ""
Write-Host "==> Documents\BannerlordCrash* / CrashReports / etc.  newest" -ForegroundColor Cyan
foreach ($p in @(
    (Join-Path $cfgRoot 'CrashLogs'),
    (Join-Path $cfgRoot 'CrashReports'),
    (Join-Path $cfgRoot 'BannerlordCrashes'),
    'C:\Users\Steve\Desktop'
)) {
    if (Test-Path $p) {
        $hits = Get-ChildItem $p -Filter '*.htm*' -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-30) }
        if ($hits) {
            foreach ($h in $hits) {
                Write-Host ("  {0,8:N0}B  {1}" -f $h.Length, $h.FullName)
            }
        }
    }
}

Write-Host ""
Write-Host "==> Crest.MCM.UI Patches/* — what does MCMUISubModule try to harmony-patch?" -ForegroundColor Cyan
$patchDir = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI\Patches'
if (Test-Path $patchDir) {
    Get-ChildItem $patchDir -Filter '*.cs' | ForEach-Object {
        $name = $_.BaseName
        $hp = Select-String -Path $_.FullName -Pattern '\[Harmony(Patch|Postfix|Prefix|Transpiler)\]|HarmonyMethod|nameof\(' -List
        Write-Host ("  {0,-50}" -f $name)
    }
}
