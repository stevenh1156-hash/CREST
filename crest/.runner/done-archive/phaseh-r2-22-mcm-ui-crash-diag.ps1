$ErrorActionPreference = 'Continue'

$documents = [Environment]::GetFolderPath('MyDocuments')
$cfgRoot   = Join-Path $documents 'Mount and Blade II Bannerlord'

Write-Host "==> ModLogs (newest, last 200 lines)" -ForegroundColor Cyan
$latest = Get-ChildItem (Join-Path $cfgRoot 'Configs\ModLogs') -Filter 'default*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latest) {
    Write-Host ("  reading: " + $latest.FullName + "  modified " + $latest.LastWriteTime)
    Get-Content $latest.FullName -Tail 200 | ForEach-Object { Write-Host ("    " + $_) }
}

Write-Host ""
Write-Host "==> runtime.log (last 80 lines)" -ForegroundColor Cyan
$rl = 'C:\dev\bannerlord\crest\runtime.log'
if (Test-Path $rl) {
    $f = Get-Item $rl
    Write-Host ("  size: " + $f.Length + "B  modified: " + $f.LastWriteTime)
    Get-Content $rl -Tail 80 | ForEach-Object { Write-Host ("    " + $_) }
}

Write-Host ""
Write-Host "==> BEW error reports dropped recently" -ForegroundColor Cyan
$crestRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'
foreach ($pattern in @('*.htm','*.html','crashreport*','error*')) {
    Get-ChildItem $crestRoot -Filter $pattern -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-30) } |
        ForEach-Object { Write-Host ("  " + $_.Length + "B  " + $_.LastWriteTime + "  " + $_.FullName) }
}

Write-Host ""
Write-Host "==> Documents Crash folders newest entries (last 30 min)" -ForegroundColor Cyan
foreach ($p in @(
    (Join-Path $cfgRoot 'CrashLogs'),
    (Join-Path $cfgRoot 'CrashReports'),
    (Join-Path $cfgRoot 'BannerlordCrashes'),
    'C:\Users\Steve\Desktop'
)) {
    if (Test-Path $p) {
        $hits = Get-ChildItem $p -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-30) }
        if ($hits) {
            foreach ($h in $hits) {
                Write-Host ("  " + $h.Length + "B  " + $h.FullName)
            }
        }
    }
}

Write-Host ""
Write-Host "==> Crest.MCM.UI Patches list" -ForegroundColor Cyan
$patchDir = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI\Patches'
if (Test-Path $patchDir) {
    Get-ChildItem $patchDir -Filter '*.cs' | ForEach-Object {
        Write-Host ("  " + $_.BaseName)
    }
}
