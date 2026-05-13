$ErrorActionPreference = 'Continue'
$documents = [Environment]::GetFolderPath('MyDocuments')
$cfgRoot   = Join-Path $documents 'Mount and Blade II Bannerlord'

Write-Host "==> Latest ModLogs/default*.log -- last 250 lines" -ForegroundColor Cyan
$latest = Get-ChildItem (Join-Path $cfgRoot 'Configs\ModLogs') -Filter 'default*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latest) {
    Write-Host ("  reading: " + $latest.FullName + "  modified " + $latest.LastWriteTime)
    Get-Content $latest.FullName -Tail 250 | ForEach-Object { Write-Host ("    " + $_) }
}

Write-Host ""
Write-Host "==> any new BEW or runtime logs since 21:30" -ForegroundColor Cyan
foreach ($p in @(
    'C:\dev\bannerlord\crest\runtime.log',
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'
)) {
    if (Test-Path $p) {
        if ((Get-Item $p).PSIsContainer) {
            Get-ChildItem $p -Filter '*.log','*.htm' -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-30) } |
                ForEach-Object { Write-Host ("  recent: " + $_.FullName + "  " + $_.LastWriteTime) }
        } else {
            $f = Get-Item $p
            Write-Host ("  " + $f.FullName + "  " + $f.Length + "B  " + $f.LastWriteTime)
        }
    }
}
