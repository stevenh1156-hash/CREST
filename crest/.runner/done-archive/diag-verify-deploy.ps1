$ErrorActionPreference = 'Continue'

$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
$crestRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'

Write-Host "==> Deployed bundle file timestamps (most recent first):" -ForegroundColor Cyan
Get-ChildItem $bin -File | Sort-Object LastWriteTime -Descending | Select-Object -First 10 | ForEach-Object {
    Write-Host ("    {0:yyyy-MM-dd HH:mm:ss}  {1,9:N0}B  {2}" -f $_.LastWriteTime, $_.Length, $_.Name)
}

Write-Host ""
Write-Host "==> Deployed SubModule.xml content:" -ForegroundColor Cyan
$xml = Join-Path $crestRoot 'SubModule.xml'
if (Test-Path $xml) {
    Write-Host ("    mtime: {0}" -f (Get-Item $xml).LastWriteTime)
    Get-Content $xml | Select-Object -First 50 | ForEach-Object { Write-Host "    $_" }
}

Write-Host ""
Write-Host "==> Verifying class FQNs in built Crest.ButterLib.dll" -ForegroundColor Cyan
Add-Type -Path 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'
$dll = Join-Path $bin 'Crest.ButterLib.dll'
if (Test-Path $dll) {
    $a = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dll)
    try {
        Write-Host ("    Asm: {0} v{1}" -f $a.Name.Name, $a.Name.Version)
        # Find ButterLibSubModule class
        $found = $false
        foreach ($t in $a.MainModule.Types) {
            if ($t.Name -eq 'ButterLibSubModule') {
                Write-Host ("    Type FQN: {0}" -f $(if ($t.Namespace) { "$($t.Namespace).$($t.Name)" } else { $t.Name }))
                Write-Host ("    Visibility: IsPublic={0}, IsNotPublic={1}" -f $t.IsPublic, $t.IsNotPublic)
                $found = $true
                break
            }
        }
        if (-not $found) {
            Write-Host "    ButterLibSubModule NOT FOUND - DLL is wrong" -ForegroundColor Red
        }
    } finally { $a.Dispose() }
} else {
    Write-Host "    Crest.ButterLib.dll MISSING from deployed bin" -ForegroundColor Red
}

# List ALL DLLs in bin
Write-Host ""
Write-Host "==> All DLLs in deployed bin:" -ForegroundColor Cyan
$count = (Get-ChildItem $bin -File | Measure-Object).Count
Write-Host "    $count total files"
Get-ChildItem $bin -Filter '*.dll' | Sort-Object Name | ForEach-Object {
    Write-Host ("    {0}" -f $_.Name)
}
