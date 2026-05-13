$ErrorActionPreference = 'Continue'
$outFile = 'C:\dev\bannerlord\crest\diag-output.txt'
'Dump string scan - ' + (Get-Date -Format 'HH:mm:ss') | Set-Content $outFile

# Search broadly for ANY fresh files Bannerlord might have written for the crash
$cutoff = (Get-Date).AddMinutes(-15)
'=== All fresh files mentioning Bannerlord/TaleWorlds anywhere we can read ===' | Add-Content $outFile
$searchRoots = @(
    "$env:USERPROFILE\Documents",
    "$env:USERPROFILE\OneDrive\Documents",
    "$env:USERPROFILE\AppData\Local",
    "$env:USERPROFILE\AppData\Roaming",
    "C:\ProgramData\Microsoft\Windows\WER",
    "C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord"
)
$bannerlordPattern = '*Mount.*Blade*|*Bannerlord*|*TaleWorlds*|*Crashes*|*BUTR*|*Crest*|*CREST*'

$candidates = @()
foreach ($root in $searchRoots) {
    if (Test-Path $root) {
        $candidates += Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.LastWriteTime -gt $cutoff -and
                ($_.FullName -match 'Bannerlord|TaleWorlds|Crashes|BUTR|Crest|CREST|\.dmp$|\.WER$' -and
                 $_.Name -notmatch '\.bak$|\.old$')
            }
    }
}
$candidates = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 30 -Unique
"  $($candidates.Count) files in last 15min:" | Add-Content $outFile
foreach ($f in $candidates) {
    $age = ((Get-Date) - $f.LastWriteTime).TotalMinutes
    "    {0:N0}m  {1,8:N1}KB  {2}" -f $age, ($f.Length/1KB), $f.FullName | Add-Content $outFile
}

# Find the latest WER dump and string-scan it for exception type names + messages
'' | Add-Content $outFile
'=== Latest WER dump string-scan ===' | Add-Content $outFile
$werTemp = 'C:\ProgramData\Microsoft\Windows\WER\Temp'
$werArch = 'C:\ProgramData\Microsoft\Windows\WER\ReportArchive'
$dumpFiles = @()
if (Test-Path $werTemp) {
    $dumpFiles += Get-ChildItem $werTemp -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '\.dmp$' -and $_.LastWriteTime -gt $cutoff }
}
if (Test-Path $werArch) {
    $dumpFiles += Get-ChildItem $werArch -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '\.dmp$' -and $_.LastWriteTime -gt $cutoff }
}
$latestDump = $dumpFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latestDump) {
    "  scanning $($latestDump.FullName) ($($latestDump.Length) bytes)..." | Add-Content $outFile

    # Read raw bytes, look for ASCII strings related to exceptions/types
    $bytes = [System.IO.File]::ReadAllBytes($latestDump.FullName)
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)

    # Candidate patterns (exception type names, common message fragments)
    $patterns = @(
        '[A-Za-z]{4,}Exception',
        'Could not load file',
        'Could not load type',
        'Type ''[^'']+'' is not loadable',
        'The type initializer for',
        'Method not found:',
        'Field not found:',
        'BetterExceptionWindow\.[A-Za-z]+',
        'Crest\.[A-Za-z.]+',
        'Bannerlord\.[A-Za-z.]+\.SubModule',
        'OnSubModuleLoad',
        'Newtonsoft\.Json',
        '0Harmony',
        'TaleWorlds\.[A-Z][A-Za-z.]+\.[A-Z][A-Za-z]+'
    )
    $unique = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($pat in $patterns) {
        $regexMatches = [regex]::Matches($text, $pat) | Select-Object -First 100
        foreach ($m in $regexMatches) {
            $val = $m.Value.Trim()
            if ($val.Length -ge 4 -and $val.Length -le 200) { [void]$unique.Add($val) }
        }
    }
    $list = $unique | Sort-Object
    "  found $($list.Count) candidate strings:" | Add-Content $outFile
    $list | ForEach-Object { "    $_" | Add-Content $outFile }
} else {
    "  No fresh dump file found." | Add-Content $outFile
}
'' | Add-Content $outFile
'=== Done ===' | Add-Content $outFile
