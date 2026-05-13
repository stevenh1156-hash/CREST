$ErrorActionPreference = 'Stop'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$staging = 'C:\dev\bannerlord\crest\dist\CREST'
$src = Join-Path $staging 'SubModule.xml'
$dst = Join-Path $gameRoot 'Modules\CREST\SubModule.xml'

Write-Host '==> Read staging' -ForegroundColor Cyan
$content = [System.IO.File]::ReadAllText($src)
Write-Host ('   length: ' + $content.Length + ' chars')

Write-Host ''
Write-Host '==> Delete deployed' -ForegroundColor Cyan
if (Test-Path $dst) { Remove-Item $dst -Force }

Write-Host '==> Wait for filesystem (in case AV scanning lags)' -ForegroundColor Cyan
Start-Sleep -Milliseconds 200

Write-Host '==> Write deployed via WriteAllText (no buffering)' -ForegroundColor Cyan
[System.IO.File]::WriteAllText($dst, $content, [System.Text.Encoding]::UTF8)

Write-Host '==> Verify size' -ForegroundColor Cyan
$df = Get-Item $dst
$lines = (Get-Content $dst).Count
Write-Host ('   ' + $df.Length + ' bytes, ' + $lines + ' lines')

# Multiple verifications
Start-Sleep -Milliseconds 500
$df2 = Get-Item $dst
$lines2 = (Get-Content $dst).Count
Write-Host ('   after 500ms: ' + $df2.Length + ' bytes, ' + $lines2 + ' lines')

Start-Sleep -Milliseconds 2000
$df3 = Get-Item $dst
$lines3 = (Get-Content $dst).Count
Write-Host ('   after 2.5s: ' + $df3.Length + ' bytes, ' + $lines3 + ' lines')

Write-Host ''
Write-Host '==> If size shrank between samples, something is corrupting the file in real time.' -ForegroundColor Yellow
