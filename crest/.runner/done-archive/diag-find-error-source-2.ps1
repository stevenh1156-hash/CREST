$ErrorActionPreference = 'Continue'

$phrases = @('Error while loading','submodule could not be loaded','stability issues','due to a dependency')

$searchDirs = @(
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client',
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\bin\Win64_Shipping_Client',
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\Native\bin\Win64_Shipping_Client'
)

foreach ($phrase in $phrases) {
    Write-Host ""
    Write-Host "==> Searching for '$phrase'" -ForegroundColor Cyan
    foreach ($dir in $searchDirs) {
        if (-not (Test-Path $dir)) { continue }
        $dlls = Get-ChildItem $dir -Filter '*.dll' -ErrorAction SilentlyContinue
        foreach ($dll in $dlls) {
            try {
                $bytes = [System.IO.File]::ReadAllBytes($dll.FullName)
                $ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
                $utf16 = [System.Text.Encoding]::Unicode.GetString($bytes)
                if ($ascii -match [regex]::Escape($phrase) -or $utf16 -match [regex]::Escape($phrase)) {
                    Write-Host ("  [MATCH] {0}" -f $dll.FullName) -ForegroundColor Yellow
                }
            } catch { }
        }
    }
}

# Also search XML localization files in game folders
Write-Host ""
Write-Host "==> Searching ModuleData XML files for these phrases" -ForegroundColor Cyan
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
foreach ($phrase in $phrases) {
    Write-Host "  '$phrase':"
    $hits = Get-ChildItem -Recurse -File -Path $gameRoot -Filter '*.xml' -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -lt 5MB -and ($_.FullName -like '*Languages*' -or $_.FullName -like '*ModuleData*') } |
        ForEach-Object {
            try {
                $c = [System.IO.File]::ReadAllText($_.FullName)
                if ($c -match [regex]::Escape($phrase)) {
                    Write-Host ("    [XML] {0}" -f $_.FullName) -ForegroundColor Yellow
                }
            } catch { }
        }
}
