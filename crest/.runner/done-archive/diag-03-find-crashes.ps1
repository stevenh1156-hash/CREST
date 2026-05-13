Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force
$ErrorActionPreference = 'Continue'
$outFile = 'C:\dev\bannerlord\crest\diag-output.txt'
'Crest diagnostic - ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Set-Content $outFile

# 1. Find where Documents actually is (OneDrive can redirect this)
$docs = [Environment]::GetFolderPath('MyDocuments')
"Documents folder: $docs" | Add-Content $outFile

$blDocs = Join-Path $docs 'Mount and Blade II Bannerlord'
"Bannerlord docs: $blDocs (exists: $(Test-Path $blDocs))" | Add-Content $outFile

# 2. List subfolders if it exists
if (Test-Path $blDocs) {
    "" | Add-Content $outFile
    "=== Subfolders of Bannerlord docs ===" | Add-Content $outFile
    Get-ChildItem $blDocs -Directory | ForEach-Object {
        $fileCount = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
        "  $($_.Name) ($fileCount files, last modified $($_.LastWriteTime))" | Add-Content $outFile
    }

    # 3. Recent files (last 60 min)
    "" | Add-Content $outFile
    "=== Recent files (last 60 min) ===" | Add-Content $outFile
    $cutoff = (Get-Date).AddMinutes(-60)
    Get-ChildItem $blDocs -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $cutoff } |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object {
            $age = ((Get-Date) - $_.LastWriteTime).TotalMinutes
            $age0 = [math]::Round($age, 0)
            $kb = [math]::Round($_.Length / 1KB, 1)
            "  ${age0}m  ${kb}KB  $($_.FullName)" | Add-Content $outFile
        }

    # 4. Tail any recent log/text/json files
    "" | Add-Content $outFile
    "=== Tails of recent log files ===" | Add-Content $outFile
    $logs = Get-ChildItem $blDocs -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $cutoff -and $_.Extension -in '.txt','.log','.html','.json' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 5
    foreach ($f in $logs) {
        "" | Add-Content $outFile
        "----- $($f.FullName) -----" | Add-Content $outFile
        try {
            Get-Content $f.FullName -Tail 80 -ErrorAction Stop | ForEach-Object {
                "    $_" | Add-Content $outFile
            }
        } catch {
            "    (read error: $_)" | Add-Content $outFile
        }
    }

    # 5. LauncherData.xml mod state
    "" | Add-Content $outFile
    "=== Launcher mod state ===" | Add-Content $outFile
    $cfg = Join-Path $blDocs 'Configs\LauncherData.xml'
    if (Test-Path $cfg) {
        try {
            $xml = [xml](Get-Content $cfg -Raw)
            foreach ($m in $xml.SelectNodes('//SingleplayerData/ModDatas/UserModData')) {
                $marker = if ($m.IsSelected -eq 'true') { 'X' } else { ' ' }
                "  [$marker] $($m.Id)" | Add-Content $outFile
            }
        } catch {
            "  (parse error: $_)" | Add-Content $outFile
        }
    } else {
        "  LauncherData.xml not found at $cfg" | Add-Content $outFile
    }
}

# 6. CREST module integrity
"" | Add-Content $outFile
"=== CREST module integrity ===" | Add-Content $outFile
$crestDir = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'
$sm = Join-Path $crestDir 'SubModule.xml'
if (Test-Path $sm) {
    try {
        $xml = [xml](Get-Content $sm -Raw)
        "  SubModule.xml parsed OK" | Add-Content $outFile
        "  Id=$($xml.Module.Id.value)  Name=$($xml.Module.Name.value)  Version=$($xml.Module.Version.value)" | Add-Content $outFile
        foreach ($s in $xml.Module.SubModules.SubModule) {
            "    SubModule: $($s.Name.value) -> $($s.DLLName.value) :: $($s.SubModuleClassType.value)" | Add-Content $outFile
        }
    } catch {
        "  PARSE ERROR: $_" | Add-Content $outFile
    }
}

"" | Add-Content $outFile
"=== Done ===" | Add-Content $outFile
