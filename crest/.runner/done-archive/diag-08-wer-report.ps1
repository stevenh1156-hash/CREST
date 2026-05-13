$ErrorActionPreference = 'Continue'
$outFile = 'C:\dev\bannerlord\crest\diag-output.txt'
'WER report read - ' + (Get-Date -Format 'HH:mm:ss') | Set-Content $outFile

# Find the latest WER report archive folder for our crash
$wer = 'C:\ProgramData\Microsoft\Windows\WER\ReportArchive'
"==> Looking for WER report archives..." | Add-Content $outFile
if (-not (Test-Path $wer)) {
    "  $wer not accessible" | Add-Content $outFile
    exit 1
}

$folders = Get-ChildItem $wer -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'AppCrash_*' -and $_.LastWriteTime -gt (Get-Date).AddMinutes(-30) } |
    Sort-Object LastWriteTime -Descending
"  Found $($folders.Count) recent crash folders." | Add-Content $outFile

foreach ($f in ($folders | Select-Object -First 5)) {
    "" | Add-Content $outFile
    "=== $($f.Name) (modified $($f.LastWriteTime)) ===" | Add-Content $outFile

    # Look for Report.wer / Report.txt / WERInternalMetadata.xml inside
    $files = Get-ChildItem $f.FullName -File -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        "  -- $($file.Name) ($($file.Length) bytes) --" | Add-Content $outFile
        if ($file.Extension -in '.txt','.wer','.xml','.csv') {
            try {
                Get-Content $file.FullName -Raw -ErrorAction Stop | Add-Content $outFile
            } catch {
                "  (read error: $_)" | Add-Content $outFile
            }
        }
    }
}

# Also check WER\Temp folder for current/in-flight reports
"" | Add-Content $outFile
"==> WER\Temp folder (in-flight reports):" | Add-Content $outFile
$tmp = 'C:\ProgramData\Microsoft\Windows\WER\Temp'
if (Test-Path $tmp) {
    $tmpFiles = Get-ChildItem $tmp -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-15) } |
        Sort-Object LastWriteTime -Descending
    "  $($tmpFiles.Count) recent files" | Add-Content $outFile
    foreach ($t in ($tmpFiles | Select-Object -First 8)) {
        if ($t.Extension -in '.txt','.xml','.csv' -and $t.Length -lt 100KB) {
            "" | Add-Content $outFile
            "  -- $($t.Name) ($($t.Length) bytes) --" | Add-Content $outFile
            try {
                Get-Content $t.FullName -Raw -ErrorAction Stop | Add-Content $outFile
            } catch {
                "  (read error: $_)" | Add-Content $outFile
            }
        } else {
            "  $($t.Name) - $($t.Length) bytes (skipped)" | Add-Content $outFile
        }
    }
}
