$ErrorActionPreference = 'Continue'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$installBin = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'
$gameBin = Join-Path $gameRoot 'bin\Win64_Shipping_Client'

Write-Host '==> CREST/bin contents (count + critical files)' -ForegroundColor Cyan
$files = Get-ChildItem $installBin -File
Write-Host ('   total: ' + $files.Count + ' files')
foreach ($n in '0Harmony.dll','Mono.Cecil.dll','Crest.Harmony.dll','Crest.ButterLib.dll','CREST.v1.4.1.dll','Bannerlord.Harmony.dll','MCMv5.dll') {
    $p = Join-Path $installBin $n
    if (Test-Path $p) {
        Write-Host ('   OK  ' + $n + '  ' + (Get-Item $p).LastWriteTime.ToString('HH:mm:ss')) -ForegroundColor Green
    } else {
        Write-Host ('   MISSING ' + $n) -ForegroundColor Red
    }
}

Write-Host ''
Write-Host '==> game bin: BLSE.Shared.dll, BLSE.AppDomainManager.dll, Bannerlord.LauncherEx.dll' -ForegroundColor Cyan
foreach ($n in 'Bannerlord.BLSE.Shared.dll','Bannerlord.BLSE.AppDomainManager.dll','Bannerlord.LauncherEx.dll','Bannerlord.BLSE.LauncherEx.exe') {
    $p = Join-Path $gameBin $n
    if (Test-Path $p) {
        Write-Host ('   OK  ' + $n + '  ' + (Get-Item $p).LastWriteTime.ToString('HH:mm:ss') + '  ' + ([math]::Round((Get-Item $p).Length/1KB)) + ' KB') -ForegroundColor Green
    }
}
