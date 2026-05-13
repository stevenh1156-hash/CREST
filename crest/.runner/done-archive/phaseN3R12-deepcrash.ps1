$ErrorActionPreference = 'Continue'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$docs = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Mount and Blade II Bannerlord'

Write-Host '==> All recently-modified files under Documents\...\MountAndBlade II Bannerlord' -ForegroundColor Cyan
Get-ChildItem $docs -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-20) } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 30 | ForEach-Object {
        Write-Host ('   ' + $_.LastWriteTime.ToString('HH:mm:ss') + '  ' + $_.FullName.Substring($docs.Length))
    }

Write-Host ''
Write-Host '==> All ButterLib trace logs newer than 5 min ago (full content)' -ForegroundColor Cyan
$bl = Get-ChildItem (Join-Path $docs 'Configs\ModLogs') -Filter 'butterlib*.txt' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-15) }
foreach ($f in $bl) {
    Write-Host ('--- ' + $f.Name + '  ts: ' + $f.LastWriteTime.ToString('HH:mm:ss') + ' ---')
    Get-Content $f.FullName -Tail 60 | ForEach-Object { Write-Host ('   ' + $_) }
    Write-Host ''
}

Write-Host ''
Write-Host '==> Windows Application Event Log for Bannerlord errors in last 15 min' -ForegroundColor Cyan
try {
    Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddMinutes(-15); Level=2,3} -MaxEvents 30 -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match 'Bannerlord|TaleWorlds|MountAndBlade' } |
        Select-Object -First 5 | ForEach-Object {
            Write-Host ('   ' + $_.TimeCreated.ToString('HH:mm:ss') + '  ' + $_.ProviderName + '  ' + $_.LevelDisplayName)
            $_.Message -split "`n" | Select-Object -First 12 | ForEach-Object { Write-Host ('     ' + $_) }
            Write-Host ''
        }
} catch { }

Write-Host '==> Bannerlord process running? (would mean game survived)' -ForegroundColor Cyan
Get-Process | Where-Object { $_.ProcessName -match 'Bannerlord' } | Select-Object -First 5 | Format-Table Id, ProcessName, StartTime
