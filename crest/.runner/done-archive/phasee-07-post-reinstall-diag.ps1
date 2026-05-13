$ErrorActionPreference = 'Continue'

$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\bin\Win64_Shipping_Client'
$documents = [Environment]::GetFolderPath('MyDocuments')
$cfgRoot   = Join-Path $documents 'Mount and Blade II Bannerlord'

Write-Host '==> All BLSE-related files in game bin (size + mtime)' -ForegroundColor Cyan
Get-ChildItem $bin -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like '*BLSE*' -or $_.Name -like '*LauncherEx*' -or $_.Name -like '*.config' -or $_.Name -like '*lasterror*' } |
    Sort-Object Name | ForEach-Object {
        Write-Host ('  ' + [math]::Round($_.Length/1KB) + 'KB  ' + $_.LastWriteTime + '  ' + $_.Name)
    }

Write-Host ''
Write-Host '==> BLSE_lasterror.log (latest content)' -ForegroundColor Cyan
$err = Join-Path $bin 'BLSE_lasterror.log'
if (Test-Path $err) {
    $f = Get-Item $err
    Write-Host ('  modified: ' + $f.LastWriteTime + '  size: ' + $f.Length)
    Get-Content $err | ForEach-Object { Write-Host ('  ' + $_) }
}

Write-Host ''
Write-Host '==> ModLogs latest tail (50 lines)' -ForegroundColor Cyan
$latest = Get-ChildItem (Join-Path $cfgRoot 'Configs\ModLogs') -Filter 'default*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latest) {
    Write-Host ('  reading: ' + $latest.FullName + '  modified ' + $latest.LastWriteTime)
    Get-Content $latest.FullName -Tail 50 | ForEach-Object { Write-Host ('    ' + $_) }
}

Write-Host ''
Write-Host '==> Check key .config file contents' -ForegroundColor Cyan
foreach ($n in @('TaleWorlds.MountAndBlade.Launcher.exe.config','Bannerlord.BLSE.Launcher.exe.config','Bannerlord.BLSE.LauncherEx.exe.config','Bannerlord.exe.config')) {
    $p = Join-Path $bin $n
    if (Test-Path $p) {
        Write-Host ('  -- ' + $n + ' --')
        Get-Content $p | ForEach-Object { Write-Host ('    ' + $_) }
    } else {
        Write-Host ('  MISS ' + $n)
    }
}

Write-Host ''
Write-Host '==> CREST modules state' -ForegroundColor Cyan
$modules = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules'
Get-ChildItem $modules -Directory | Where-Object { $_.Name -in @('CREST','Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen') } |
    ForEach-Object {
        $sm = Join-Path $_.FullName 'SubModule.xml'
        $kind = 'unknown'
        if (Test-Path $sm) {
            $c = Get-Content $sm -Raw
            if ($c -match 'CREST stub') { $kind = 'STUB' }
            elseif ($c -match '<Id value="CREST"') { $kind = 'CREST' }
            else { $kind = 'OTHER' }
        }
        Write-Host ('  [' + $kind + '] ' + $_.Name)
    }
