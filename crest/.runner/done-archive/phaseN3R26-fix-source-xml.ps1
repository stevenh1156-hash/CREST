$ErrorActionPreference = 'Stop'

$src = 'C:\dev\bannerlord\crest\dist\CREST\SubModule.xml'
$dst = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI\_Module\SubModule.xml'

Write-Host '==> Backup current _Module/SubModule.xml' -ForegroundColor Cyan
Copy-Item $dst ($dst + '.upstream-backup') -Force

Write-Host '==> Replace _Module/SubModule.xml with CREST staging version' -ForegroundColor Cyan
$content = [System.IO.File]::ReadAllText($src)
[System.IO.File]::WriteAllText($dst, $content, [System.Text.Encoding]::UTF8)

$lines = (Get-Content $dst).Count
Write-Host ('   wrote ' + $lines + ' lines')

Write-Host ''
Write-Host '==> Now MCM UI rebuilds will copy the CREST template instead of the upstream stub.' -ForegroundColor Yellow
