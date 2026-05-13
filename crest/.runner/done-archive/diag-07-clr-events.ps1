$ErrorActionPreference = 'Continue'
$outFile = 'C:\dev\bannerlord\crest\diag-output.txt'
'CLR event probe - ' + (Get-Date -Format 'HH:mm:ss') | Set-Content $outFile

$cutoff = (Get-Date).AddMinutes(-15)

# Specifically look for .NET Runtime events (provider name = '.NET Runtime')
"=== .NET Runtime events in last 15 min ===" | Add-Content $outFile
try {
    $clr = Get-WinEvent -FilterHashtable @{
        LogName = 'Application'
        ProviderName = '.NET Runtime'
        StartTime = $cutoff
    } -ErrorAction Stop
    "Found $($clr.Count) .NET Runtime events." | Add-Content $outFile
    foreach ($e in ($clr | Sort-Object TimeCreated -Descending | Select-Object -First 5)) {
        "" | Add-Content $outFile
        "--- Event $($e.Id) at $($e.TimeCreated) ---" | Add-Content $outFile
        $e.Message | Add-Content $outFile
    }
} catch {
    "  No .NET Runtime events found, or query error: $_" | Add-Content $outFile
}

# Also check Windows Error Reporting which sometimes has dump-time details
"" | Add-Content $outFile
"=== Windows Error Reporting events in last 15 min ===" | Add-Content $outFile
try {
    $wer = Get-WinEvent -FilterHashtable @{
        LogName = 'Application'
        ProviderName = 'Windows Error Reporting'
        StartTime = $cutoff
    } -ErrorAction Stop
    "Found $($wer.Count) WER events." | Add-Content $outFile
    foreach ($e in ($wer | Sort-Object TimeCreated -Descending | Select-Object -First 3)) {
        "" | Add-Content $outFile
        "--- Event $($e.Id) at $($e.TimeCreated) ---" | Add-Content $outFile
        ($e.Message -split "`n" | Select-Object -First 30) | ForEach-Object { "  $_" | Add-Content $outFile }
    }
} catch {
    "  No WER events found, or query error: $_" | Add-Content $outFile
}

# Also look for Application Hangs and any Bannerlord-related events
"" | Add-Content $outFile
"=== Any Application log event mentioning Bannerlord or Crest in last 15 min ===" | Add-Content $outFile
try {
    Get-WinEvent -FilterHashtable @{
        LogName = 'Application'
        StartTime = $cutoff
    } -ErrorAction Stop |
    Where-Object { $_.Message -match 'Bannerlord|TaleWorlds|Crest|CREST|MountAndBlade|Harmony|ButterLib|UIExtender|MCM' } |
    Select-Object -First 8 |
    ForEach-Object {
        "" | Add-Content $outFile
        "--- $($_.TimeCreated) [$($_.ProviderName)] Event $($_.Id) ---" | Add-Content $outFile
        ($_.Message -split "`n" | Select-Object -First 25) | ForEach-Object { "  $_" | Add-Content $outFile }
    }
} catch {
    "  query error: $_" | Add-Content $outFile
}

# Also check Documents\Mount and Blade II Bannerlord\Logs for fresh files (real-time)
"" | Add-Content $outFile
"=== Documents\Logs current state ===" | Add-Content $outFile
$logs = "$([Environment]::GetFolderPath('MyDocuments'))\Mount and Blade II Bannerlord\Logs"
if (Test-Path $logs) {
    Get-ChildItem $logs -File | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | ForEach-Object {
        "  $($_.LastWriteTime)  $([math]::Round($_.Length/1KB,1))KB  $($_.Name)" | Add-Content $outFile
    }
}
"" | Add-Content $outFile
"=== Done ===" | Add-Content $outFile
