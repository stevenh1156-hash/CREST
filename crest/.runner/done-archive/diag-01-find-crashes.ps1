# Hunt for crash artifacts across all known Bannerlord crash/log locations.
$ErrorActionPreference = 'Continue'

$candidates = @(
    "$env:USERPROFILE\Documents\Mount and Blade II Bannerlord\logs",
    "$env:USERPROFILE\Documents\Mount and Blade II Bannerlord\Crashes",
    "$env:USERPROFILE\Documents\Mount and Blade II Bannerlord\BUTR_CrashReports",
    "$env:USERPROFILE\Documents\Mount and Blade II Bannerlord\CrashUploads",
    "$env:USERPROFILE\AppData\Local\Mount and Blade II Bannerlord\logs",
    "$env:USERPROFILE\AppData\Local\Mount and Blade II Bannerlord\Crashes",
    "$env:USERPROFILE\AppData\Local\Temp\Mount and Blade II Bannerlord",
    "$env:LOCALAPPDATA\Temp\Mount and Blade II Bannerlord",
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\bin\Win64_Shipping_Client'
)

Write-Host "==> Searching for recent crash/log files (last 30 minutes):" -ForegroundColor Cyan
$cutoff = (Get-Date).AddMinutes(-30)
$found = @()
foreach ($d in $candidates) {
    if (Test-Path $d) {
        $files = Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt $cutoff }
        foreach ($f in $files) {
            $found += $f
            $age = ((Get-Date) - $f.LastWriteTime).TotalMinutes
            Write-Host ("    {0,5:N0}m  {1,8:N1}KB  {2}" -f $age, ($f.Length/1KB), $f.FullName) -ForegroundColor Green
        }
    } else {
        Write-Host ("    (path not found: $d)") -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "==> Found $($found.Count) recent files." -ForegroundColor Cyan
Write-Host ""

# Dump tail of any .txt or .log file found
$logFiles = $found | Where-Object { $_.Extension -in '.txt','.log','.html','.json' }
foreach ($f in $logFiles) {
    Write-Host "==== TAIL OF $($f.Name) ====" -ForegroundColor Yellow
    Get-Content $f.FullName -Tail 80 | ForEach-Object { Write-Host "    $_" }
    Write-Host ""
}

# Also: list mods that were last loaded so we can see if legacy BUTR was enabled
Write-Host "==> Bannerlord launcher config (which mods were enabled):" -ForegroundColor Cyan
$cfg = "$env:USERPROFILE\Documents\Mount and Blade II Bannerlord\Configs\LauncherData.xml"
if (Test-Path $cfg) {
    $xml = [xml](Get-Content $cfg)
    $modsNode = $xml.SelectNodes('//SingleplayerData/ModDatas/UserModData')
    Write-Host "    Singleplayer mods (in load order):"
    foreach ($m in $modsNode) {
        $isSel = $m.IsSelected
        $color = if ($isSel -eq 'true') { 'Green' } else { 'DarkGray' }
        $marker = if ($isSel -eq 'true') { 'X' } else { ' ' }
        Write-Host ("       [{0}] {1}" -f $marker, $m.Id) -ForegroundColor $color
    }
} else {
    Write-Host "    (LauncherData.xml not found at $cfg)" -ForegroundColor DarkGray
}

exit 0
