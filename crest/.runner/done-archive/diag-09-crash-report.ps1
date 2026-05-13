$ErrorActionPreference = 'Continue'
$outFile = 'C:\dev\bannerlord\crest\diag-output.txt'
'Crash report fetch - ' + (Get-Date -Format 'HH:mm:ss') | Set-Content $outFile

# Game version: read TaleWorlds.Native.dll version + Version.xml if present
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
'=== Game version detection ===' | Add-Content $outFile
$nativeXml = Join-Path $gameRoot 'Modules\Native\SubModule.xml'
if (Test-Path $nativeXml) {
    try {
        $nx = [xml](Get-Content $nativeXml -Raw)
        "  Native module Version: $($nx.Module.Version.value)" | Add-Content $outFile
    } catch { "  parse error: $_" | Add-Content $outFile }
}
$exe = Join-Path $gameRoot 'bin\Win64_Shipping_Client\TaleWorlds.MountAndBlade.Launcher.exe'
if (Test-Path $exe) {
    $vinfo = (Get-Item $exe).VersionInfo
    "  Launcher.exe FileVersion=$($vinfo.FileVersion) ProductVersion=$($vinfo.ProductVersion)" | Add-Content $outFile
}
$nativeDll = Join-Path $gameRoot 'bin\Win64_Shipping_Client\TaleWorlds.Native.dll'
if (Test-Path $nativeDll) {
    $vinfo = (Get-Item $nativeDll).VersionInfo
    "  TaleWorlds.Native.dll FileVersion=$($vinfo.FileVersion) ProductVersion=$($vinfo.ProductVersion)" | Add-Content $outFile
}

# Crash reports - check both Documents and OneDrive
$docs = [Environment]::GetFolderPath('MyDocuments')
$candidates = @(
    "$docs\Mount and Blade II Bannerlord\Crashes",
    "$env:USERPROFILE\Documents\Mount and Blade II Bannerlord\Crashes",
    "$env:USERPROFILE\OneDrive\Documents\Mount and Blade II Bannerlord\Crashes",
    "$docs\Mount and Blade II Bannerlord\BUTR_CrashReports",
    "$env:USERPROFILE\OneDrive\Documents\Mount and Blade II Bannerlord\BUTR_CrashReports"
)

'' | Add-Content $outFile
'=== Crash reports in last 15 min ===' | Add-Content $outFile
$cutoff = (Get-Date).AddMinutes(-15)
$found = @()
foreach ($d in $candidates) {
    if (Test-Path $d) {
        "  Checking $d" | Add-Content $outFile
        $files = Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt $cutoff }
        $found += $files
        foreach ($f in $files) {
            $age = ((Get-Date) - $f.LastWriteTime).TotalMinutes
            ("    {0:N0}m  {1:N1}KB  {2}" -f $age, ($f.Length/1KB), $f.FullName) | Add-Content $outFile
        }
    }
}
"  Total fresh crash files: $($found.Count)" | Add-Content $outFile

# Read text-like crash reports
'' | Add-Content $outFile
'=== Crash report contents ===' | Add-Content $outFile
$readable = $found | Where-Object { $_.Extension -in '.txt','.html','.log','.json','.xml' -or $_.Length -lt 200KB }
foreach ($f in ($readable | Sort-Object LastWriteTime -Descending | Select-Object -First 3)) {
    '' | Add-Content $outFile
    "----- $($f.FullName) -----" | Add-Content $outFile
    try {
        $content = Get-Content $f.FullName -Raw -ErrorAction Stop
        # If HTML, strip tags for readability; otherwise dump first 6000 chars
        if ($f.Extension -eq '.html' -or $content -match '^<!DOCTYPE|^<html') {
            $stripped = $content -replace '<[^>]+>',' '
            $stripped = $stripped -replace '\s+',' '
            $stripped = $stripped -replace '&nbsp;',' '
            $stripped = $stripped -replace '&amp;','&'
            $stripped = $stripped -replace '&lt;','<'
            $stripped = $stripped -replace '&gt;','>'
            ($stripped.Substring(0, [Math]::Min(8000, $stripped.Length))) | Add-Content $outFile
        } else {
            ($content.Substring(0, [Math]::Min(8000, $content.Length))) | Add-Content $outFile
        }
    } catch {
        "  (read error: $_)" | Add-Content $outFile
    }
}

# Also fresh WER reports as backup
'' | Add-Content $outFile
'=== Fresh CLR WER reports ===' | Add-Content $outFile
$wer = 'C:\ProgramData\Microsoft\Windows\WER\ReportArchive'
if (Test-Path $wer) {
    Get-ChildItem $wer -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $cutoff -and $_.Name -like 'AppCrash_*' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 2 |
        ForEach-Object {
            "" | Add-Content $outFile
            "  $($_.Name)" | Add-Content $outFile
            $reportWer = Join-Path $_.FullName 'Report.wer'
            if (Test-Path $reportWer) {
                $sigs = (Get-Content $reportWer | Select-String -Pattern '^Sig\[.+\]\.Value=|^DynamicSig\[2[0-9]\]\.Value=|^EventType=|^TargetAppId=')
                $sigs | ForEach-Object { "    $_" | Add-Content $outFile }
            }
        }
}
'' | Add-Content $outFile
'=== Done ===' | Add-Content $outFile
