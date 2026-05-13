$ErrorActionPreference = 'Continue'
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
$xmlPath = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\SubModule.xml'

Write-Host "==> Inspecting bin folder content vs SubModule.xml expectations" -ForegroundColor Cyan

# What does the SubModule.xml expect?
$xml = [xml](Get-Content $xmlPath -Raw)
$expected = New-Object System.Collections.Generic.HashSet[string]
foreach ($s in $xml.Module.SubModules.SubModule) {
    [void]$expected.Add($s.DLLName.value)
    if ($s.Assemblies -and $s.Assemblies.Assembly) {
        foreach ($a in @($s.Assemblies.Assembly)) {
            [void]$expected.Add($a.value)
        }
    }
}

Write-Host ""
Write-Host "==> SubModule.xml-referenced files:" -ForegroundColor Cyan
foreach ($n in ($expected | Sort-Object)) {
    $path = Join-Path $bin $n
    $exists = Test-Path $path
    if ($exists) {
        $sz = (Get-Item $path).Length
        Write-Host ("    [OK ] {0,9:N0}B  {1}" -f $sz, $n) -ForegroundColor Green
    } else {
        Write-Host ("    [MISS]            {0}" -f $n) -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "==> ALL files in bin folder:" -ForegroundColor Cyan
Get-ChildItem $bin -File | Sort-Object Name | ForEach-Object {
    Write-Host ("    {0,9:N0}B  {1}" -f $_.Length, $_.Name)
}

Write-Host ""
Write-Host "==> runtime.log progress (last 20 lines):" -ForegroundColor Cyan
$log = 'C:\dev\bannerlord\crest\runtime.log'
if (Test-Path $log) {
    Get-Content $log -Tail 20 | ForEach-Object { Write-Host "    $_" }
}

Write-Host ""
Write-Host "==> runtime.log Exit/FailFast/Cannot entries:" -ForegroundColor Cyan
if (Test-Path $log) {
    Select-String -Path $log -Pattern 'Exit|FailFast|Cannot|FIRST-CHANCE|UNHANDLED|annot load' | ForEach-Object {
        Write-Host ("    line {0}: {1}" -f $_.LineNumber, $_.Line)
    }
}
