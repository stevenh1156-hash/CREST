$ErrorActionPreference = 'Continue'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$installBin = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'
$gameBin = Join-Path $gameRoot 'bin\Win64_Shipping_Client'
$docs = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Mount and Blade II Bannerlord'

Write-Host '==> CREST/bin contents RIGHT NOW (during crash dialog)' -ForegroundColor Cyan
$count = (Get-ChildItem $installBin -File -ErrorAction SilentlyContinue).Count
Write-Host ('   total: ' + $count + ' files')
foreach ($n in '0Harmony.dll','Mono.Cecil.dll','Crest.Harmony.dll','Crest.ButterLib.dll','MCMv5.dll','Bannerlord.Harmony.dll','CREST.v1.4.1.dll') {
    $p = Join-Path $installBin $n
    if (Test-Path $p) {
        Write-Host ('   OK  ' + $n + '  ts: ' + (Get-Item $p).LastWriteTime.ToString('HH:mm:ss')) -ForegroundColor Green
    } else {
        Write-Host ('   MISSING ' + $n) -ForegroundColor Red
    }
}

Write-Host ''
Write-Host '==> Bannerlord process running?' -ForegroundColor Cyan
$bp = Get-Process -Name Bannerlord*,TaleWorlds* -ErrorAction SilentlyContinue
foreach ($p in $bp) {
    Write-Host ('   PID ' + $p.Id + '  ' + $p.ProcessName + '  started ' + $p.StartTime.ToString('HH:mm:ss'))
}

Write-Host ''
Write-Host '==> Latest default*.log (full last 100 lines)' -ForegroundColor Cyan
$gameLog = Get-ChildItem (Join-Path $docs 'Configs\ModLogs') -Filter 'default*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($gameLog) {
    Write-Host ('   file: ' + $gameLog.Name + '  ts: ' + $gameLog.LastWriteTime.ToString('HH:mm:ss'))
    Get-Content $gameLog.FullName -Tail 100 | ForEach-Object { Write-Host ('   ' + $_) }
}

Write-Host ''
Write-Host '==> Recent Windows app errors' -ForegroundColor Cyan
try {
    Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddMinutes(-5); Level=2} -MaxEvents 10 -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match 'Bannerlord|TaleWorlds|MountAndBlade' } |
        Select-Object -First 3 | ForEach-Object {
            Write-Host ('   ' + $_.TimeCreated.ToString('HH:mm:ss') + '  ' + $_.ProviderName)
            $_.Message -split "`n" | Select-Object -First 8 | ForEach-Object { Write-Host ('     ' + $_) }
        }
} catch { }
