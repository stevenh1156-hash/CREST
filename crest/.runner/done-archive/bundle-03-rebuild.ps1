Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Rebuilding bundle with corrected allowlist..." -ForegroundColor Cyan
$ok = Build-CrestBundle -SkipBuild
if (-not $ok) { exit 1 }

Write-Host "`n==> Bundle audit:" -ForegroundColor Cyan
$bin = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client'
$dlls = Get-ChildItem $bin -Filter '*.dll' | Sort-Object Name
Write-Host ("    Total: {0} DLLs, {1:N1}KB" -f $dlls.Count, (($dlls | Measure-Object Length -Sum).Sum/1KB))
Write-Host ""
$dlls | ForEach-Object {
    Write-Host ("    {0,9:N1}KB  {1}" -f ($_.Length/1KB), $_.Name)
}

Write-Host ""
Write-Host "==> Cross-check against SubModule.xml DLLName/Assembly references..." -ForegroundColor Cyan
$xml = [xml](Get-Content 'C:\dev\bannerlord\crest\dist\CREST\SubModule.xml')
$expected = @()
foreach ($sm in $xml.Module.SubModules.SubModule) {
    if ($sm.DLLName.value) { $expected += $sm.DLLName.value }
    foreach ($a in $sm.Assemblies.Assembly) { if ($a.value) { $expected += $a.value } }
}
$expected = $expected | Sort-Object -Unique
Write-Host "    SubModule.xml references $($expected.Count) DLLs:"
$missing = 0
foreach ($e in $expected) {
    if (Test-Path (Join-Path $bin $e)) {
        Write-Host ("    OK   {0}" -f $e) -ForegroundColor Green
    } else {
        Write-Host ("    MISS {0}" -f $e) -ForegroundColor Red
        $missing++
    }
}

if ($missing -eq 0) {
    Write-Host "`n==> Repackaging zip..." -ForegroundColor Cyan
    $zip = New-CrestZip
    Write-Host "==> Bundle complete and consistent with SubModule.xml" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n==> $missing DLLs missing from bundle but referenced by SubModule.xml" -ForegroundColor Red
    exit 1
}
