$ErrorActionPreference = 'Continue'

# Search all our DLLs (and game DLLs) for the phrase "dependency conflict"
$searchPhrase = 'dependency conflict'
Write-Host "==> Searching for the phrase '$searchPhrase' in DLL string tables" -ForegroundColor Cyan

$searchDirs = @(
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client',
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\bin\Win64_Shipping_Client',
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\Native\bin\Win64_Shipping_Client',
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\SandBox\bin\Win64_Shipping_Client',
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\StoryMode\bin\Win64_Shipping_Client'
)

foreach ($dir in $searchDirs) {
    if (-not (Test-Path $dir)) { continue }
    $dlls = Get-ChildItem $dir -Filter '*.dll' -ErrorAction SilentlyContinue
    foreach ($dll in $dlls) {
        try {
            # Read raw bytes and search for ASCII + UTF-16 strings
            $bytes = [System.IO.File]::ReadAllBytes($dll.FullName)
            $asciiStr = [System.Text.Encoding]::ASCII.GetString($bytes)
            if ($asciiStr -match $searchPhrase) {
                Write-Host ("  [ASCII match] {0,8:N0}KB  {1}" -f ($dll.Length/1KB), $dll.FullName) -ForegroundColor Yellow
            }
            $utf16Str = [System.Text.Encoding]::Unicode.GetString($bytes)
            if ($utf16Str -match $searchPhrase) {
                Write-Host ("  [UTF16 match] {0,8:N0}KB  {1}" -f ($dll.Length/1KB), $dll.FullName) -ForegroundColor Yellow
            }
        } catch { }
    }
}

# Also search XML localization files
Write-Host ""
Write-Host "==> Searching localization XML files" -ForegroundColor Cyan
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$xmls = Get-ChildItem -Recurse -File -Path $gameRoot -Filter '*.xml' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like '*ModuleData*Languages*' -or $_.FullName -like '*Modules*ModuleData*Languages*' }
foreach ($x in $xmls) {
    try {
        $content = [System.IO.File]::ReadAllText($x.FullName)
        if ($content -match $searchPhrase) {
            Write-Host ("  [XML] {0}" -f $x.FullName) -ForegroundColor Yellow
            # Show the matching line
            $content -split "`n" | Where-Object { $_ -match $searchPhrase } | Select-Object -First 2 | ForEach-Object {
                Write-Host ("    {0}" -f $_.Trim()) -ForegroundColor DarkYellow
            }
        }
    } catch { }
}

Write-Host ""
Write-Host "==> Done"
