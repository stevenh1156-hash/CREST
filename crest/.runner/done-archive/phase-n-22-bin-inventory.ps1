$ErrorActionPreference = 'Continue'

$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\bin\Win64_Shipping_Client'

Write-Host "==> Game bin contents:" -ForegroundColor Cyan
Get-ChildItem $bin -File | Sort-Object Name | ForEach-Object {
    Write-Host ("   " + $_.Name + "   " + ([math]::Round($_.Length/1KB)) + " KB")
}

Write-Host ''
Write-Host '==> Specifically: TaleWorlds.MountAndBlade.Launcher.exe vs Bannerlord.BLSE.* exes' -ForegroundColor Cyan
foreach ($name in @('TaleWorlds.MountAndBlade.Launcher.exe','Bannerlord.BLSE.LauncherEx.exe','Bannerlord.BLSE.Launcher.exe','Bannerlord.exe')) {
    $p = Join-Path $bin $name
    if (Test-Path $p) {
        $f = Get-Item $p
        Write-Host ("   FOUND " + $name + "  size=" + ([math]::Round($f.Length/1KB)) + "KB  written=" + $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
    } else {
        Write-Host ("   none  " + $name)
    }
}
