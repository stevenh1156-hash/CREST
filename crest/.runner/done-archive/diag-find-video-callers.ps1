$ErrorActionPreference = 'Continue'
Add-Type -Path 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'

$gameBin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\bin\Win64_Shipping_Client'
$nativeBin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\Native\bin\Win64_Shipping_Client'

# Find any class with "Movie", "Video", "Cinematic" related to startup/intro
Write-Host "==> All Movie/Video classes (full list)" -ForegroundColor Cyan
foreach ($dir in $gameBin, $nativeBin) {
    if (-not (Test-Path $dir)) { continue }
    foreach ($dll in (Get-ChildItem $dir -Filter '*.dll')) {
        try {
            $a = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dll.FullName)
            try {
                foreach ($t in $a.MainModule.Types) {
                    $tname = "$($t.Namespace).$($t.Name)"
                    if ($tname -match 'Movie|Video|Cinematic' -and $tname -notmatch 'CampaignBehavior|Goods|Diamond|Skill|Recipe|Hero|Workshop|Trade') {
                        Write-Host ("  TYPE: {0}  in  {1}" -f $tname, $dll.Name) -ForegroundColor Yellow
                    }
                }
            } finally { $a.Dispose() }
        } catch { }
    }
}

# Look for any method that calls PlayVideo or has TWLogo/Partners in IL
Write-Host ""
Write-Host "==> Methods that reference 'TWLogo' or 'Partners' string literals" -ForegroundColor Cyan
foreach ($dir in $gameBin, $nativeBin) {
    if (-not (Test-Path $dir)) { continue }
    foreach ($dll in (Get-ChildItem $dir -Filter '*.dll')) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($dll.FullName)
            # search for "TWLogo" as ASCII or UTF-16
            $ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
            $utf16 = [System.Text.Encoding]::Unicode.GetString($bytes)
            if ($ascii -match 'TWLogo|TWLogo_and_Partners' -or $utf16 -match 'TWLogo|TWLogo_and_Partners') {
                Write-Host ("  [HIT] {0}" -f $dll.FullName) -ForegroundColor Yellow
            }
        } catch { }
    }
}

# Search Gauntlet prefab XMLs for video references
Write-Host ""
Write-Host "==> Gauntlet prefab XMLs referencing TWLogo/Partners" -ForegroundColor Cyan
$prefabRoots = @(
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\GUI',
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\Native\GUI'
)
foreach ($root in $prefabRoots) {
    if (-not (Test-Path $root)) { continue }
    Get-ChildItem -Recurse -File -Path $root -Filter '*.xml' -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -lt 1MB } |
        ForEach-Object {
            $c = [System.IO.File]::ReadAllText($_.FullName)
            if ($c -match 'TWLogo|Partners|VideoBrush|VideoPlayer|MovieBox') {
                Write-Host ("    [{0}] {1}" -f ($_.Name), $_.FullName.Substring($root.Length))
            }
        }
}
