$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\bin\Win64_Shipping_Client'

Write-Host '==> BLSE_lasterror.log content' -ForegroundColor Cyan
$err = Join-Path $bin 'BLSE_lasterror.log'
if (Test-Path $err) {
    Get-Content $err | ForEach-Object { Write-Host ('  ' + $_) }
} else {
    Write-Host '  (none)'
}

Write-Host ''
Write-Host '==> TaleWorlds.MountAndBlade.Launcher.exe.config content' -ForegroundColor Cyan
$cfg = Join-Path $bin 'TaleWorlds.MountAndBlade.Launcher.exe.config'
if (Test-Path $cfg) {
    Get-Content $cfg | ForEach-Object { Write-Host ('  ' + $_) }
}

Write-Host ''
Write-Host '==> All BLSE .exe.config files in source repo (_Root folders)' -ForegroundColor Cyan
Get-ChildItem -Recurse 'C:\dev\bannerlord\Bannerlord.BLSE\src' -Path 'C:\dev\bannerlord\Bannerlord.BLSE\src' -Filter '*.exe.config' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like '*\_Root\*' } |
    ForEach-Object {
        $rel = $_.FullName.Replace('C:\dev\bannerlord\Bannerlord.BLSE\src\', '')
        Write-Host ('  ' + $rel)
        Write-Host '  --- content ---'
        Get-Content $_.FullName | ForEach-Object { Write-Host ('    ' + $_) }
        Write-Host ''
    }
