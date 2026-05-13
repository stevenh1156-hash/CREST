# Diagnose D.2 crash - look for crash reports, native faults, BEW output
$ErrorActionPreference = 'Continue'

Write-Host "==> Looking for BEW / BUTR crash reports..." -ForegroundColor Cyan
$crashLocations = @(
    "$env:USERPROFILE\Documents\Mount and Blade II Bannerlord\butr_crashreports",
    "$env:USERPROFILE\Documents\Mount and Blade II Bannerlord\crashes",
    "$env:USERPROFILE\Documents\Mount and Blade II Bannerlord\Logs",
    "C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST",
    "$env:USERPROFILE\AppData\Local\CrashDumps",
    "$env:USERPROFILE\AppData\Local\Temp"
)
foreach ($loc in $crashLocations) {
    if (Test-Path $loc) {
        $recent = Get-ChildItem -Path $loc -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-15) } |
            Where-Object { $_.Extension -in '.dmp','.htm','.html','.log','.txt','.json','.zip' -or $_.Name -like '*crash*' -or $_.Name -like '*Bannerlord*' } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 20
        if ($recent) {
            Write-Host ""
            Write-Host "  $loc :" -ForegroundColor Yellow
            $recent | ForEach-Object {
                Write-Host ("    {0,9:N0}KB  {1:HH:mm:ss}  {2}" -f ($_.Length/1KB), $_.LastWriteTime, $_.Name)
            }
        }
    }
}

Write-Host ""
Write-Host "==> Last 5 .NET Runtime errors in Application event log..." -ForegroundColor Cyan
$evts = Get-WinEvent -LogName Application -MaxEvents 200 -ErrorAction SilentlyContinue |
    Where-Object {
        $_.TimeCreated -gt (Get-Date).AddMinutes(-15) -and
        ($_.ProviderName -like '*Application Error*' -or
         $_.ProviderName -like '*.NET Runtime*' -or
         $_.ProviderName -eq '.NET Runtime' -or
         $_.LevelDisplayName -eq 'Error')
    } |
    Select-Object -First 5
foreach ($e in $evts) {
    Write-Host ""
    Write-Host ("  {0:HH:mm:ss} {1} (id {2}, level {3})" -f $e.TimeCreated, $e.ProviderName, $e.Id, $e.LevelDisplayName) -ForegroundColor Yellow
    $msg = $e.Message
    if ($msg.Length -gt 1500) { $msg = $msg.Substring(0,1500) + "..." }
    Write-Host $msg
}

Write-Host ""
Write-Host "==> Last WER report files (Faulting application)..." -ForegroundColor Cyan
$werDirs = @(
    "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive",
    "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue",
    "$env:USERPROFILE\AppData\Local\CrashDumps"
)
foreach ($d in $werDirs) {
    if (Test-Path $d) {
        $latest = Get-ChildItem $d -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-15) } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 3
        foreach ($folder in $latest) {
            $reportTxt = Get-ChildItem $folder.FullName -Filter 'Report.wer' -ErrorAction SilentlyContinue
            if ($reportTxt) {
                Write-Host ""
                Write-Host ("  $($folder.FullName)\Report.wer:") -ForegroundColor Yellow
                Get-Content $reportTxt.FullName -ErrorAction SilentlyContinue | Select-Object -First 30 | ForEach-Object { Write-Host "    $_" }
            }
        }
    }
}
