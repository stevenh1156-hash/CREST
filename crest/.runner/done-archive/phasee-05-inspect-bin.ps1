$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\bin\Win64_Shipping_Client'

Write-Host '==> Bannerlord game bin: BLSE-related files' -ForegroundColor Cyan
Get-ChildItem $bin -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like '*BLSE*' -or $_.Name -like '*LauncherEx*' -or $_.Name -like '*.config' } |
    Sort-Object Name | ForEach-Object {
        Write-Host ('  ' + [math]::Round($_.Length/1KB) + 'KB  ' + $_.Name)
    }

Write-Host ''
Write-Host '==> Looking for .exe.config files specifically' -ForegroundColor Cyan
foreach ($name in @('Bannerlord.BLSE.Launcher.exe.config','Bannerlord.BLSE.LauncherEx.exe.config','Bannerlord.BLSE.Standalone.exe.config','TaleWorlds.MountAndBlade.Launcher.exe.config','Bannerlord.exe.config')) {
    $p = Join-Path $bin $name
    if (Test-Path $p) {
        Write-Host ('  OK   ' + $name) -ForegroundColor Green
    } else {
        Write-Host ('  MISS ' + $name) -ForegroundColor Yellow
    }
}
