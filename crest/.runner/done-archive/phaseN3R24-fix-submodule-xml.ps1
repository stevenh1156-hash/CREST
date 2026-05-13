$ErrorActionPreference = 'Continue'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$staging = 'C:\dev\bannerlord\crest\dist\CREST'
$installCrest = Join-Path $gameRoot 'Modules\CREST'

Write-Host '==> Backup current (corrupt) SubModule.xml' -ForegroundColor Cyan
$current = Join-Path $installCrest 'SubModule.xml'
if (Test-Path $current) {
    Copy-Item $current ($current + '.corrupt-backup') -Force
    Write-Host ('   backup -> ' + $current + '.corrupt-backup')
}

Write-Host ''
Write-Host '==> Restore CREST SubModule.xml from staging' -ForegroundColor Cyan
$src = Join-Path $staging 'SubModule.xml'
Copy-Item $src $current -Force
$lines = (Get-Content $current).Count
Write-Host ('   restored ' + $current + '  (' + $lines + ' lines)') -ForegroundColor Green

# Confirm content
$content = Get-Content $current -Raw
Write-Host ('   has Crest.Harmony.dll? ' + ($content -match 'Crest\.Harmony\.dll'))
Write-Host ('   has CREST.v1.4.1.dll?  ' + ($content -match 'CREST\.v1\.4\.1\.dll'))
Write-Host ('   has Bannerlord.ModuleLoader? ' + ($content -match 'Bannerlord\.ModuleLoader'))

Write-Host ''
Write-Host '==> Now relaunch via Steam.' -ForegroundColor Yellow
