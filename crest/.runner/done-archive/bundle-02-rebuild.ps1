Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

# Clean the Harmony bin folder once to permanently remove stale Bannerlord.Harmony.dll
Write-Host "==> One-time clean of Harmony bin/obj (drops stale Bannerlord.Harmony.dll)..." -ForegroundColor DarkGray
Get-ChildItem -Recurse -Directory -Path 'C:\dev\bannerlord\Bannerlord.Harmony\src' -Filter bin -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem -Recurse -Directory -Path 'C:\dev\bannerlord\Bannerlord.Harmony\src' -Filter obj -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Rebuild Harmony (the cleaned one)
$ok = Build-CrestRepo -Name Harmony
if (-not $ok) { Write-Host "==> Harmony build failed" -ForegroundColor Red; exit 1 }

# Reassemble the bundle (skipping the rest, they're still fresh)
Write-Host "`n==> Reassembling bundle with allowlist filter..." -ForegroundColor Cyan
Build-CrestBundle -SkipBuild | Out-Null

# Audit: should be NO Bannerlord.* DLL in the bundle
Write-Host "`n==> Bundle audit: any 'Bannerlord.X.dll' files (other than ModuleLoader)?" -ForegroundColor Cyan
$staging = 'C:\dev\bannerlord\crest\dist\CREST'
$bad = Get-ChildItem (Join-Path $staging 'bin\Win64_Shipping_Client') -Filter 'Bannerlord.*.dll' |
    Where-Object { $_.Name -ne 'Bannerlord.ModuleLoader.CREST.dll' }
if ($bad) {
    Write-Host "    UNEXPECTED Bannerlord.* DLLs:" -ForegroundColor Red
    $bad | ForEach-Object { Write-Host "        $($_.Name)" }
} else {
    Write-Host "    CLEAN (only Bannerlord.ModuleLoader.CREST.dll which is correct)" -ForegroundColor Green
}

Write-Host "`n==> Final bundle file count + size:" -ForegroundColor Cyan
$bin = Join-Path $staging 'bin\Win64_Shipping_Client'
$dlls = Get-ChildItem $bin -Filter '*.dll'
Write-Host ("    {0} DLLs, total {1:N1}KB" -f $dlls.Count, (($dlls | Measure-Object Length -Sum).Sum/1KB))

# Now also build the zip
Write-Host "`n==> Packaging zip..." -ForegroundColor Cyan
$zip = New-CrestZip
exit 0
