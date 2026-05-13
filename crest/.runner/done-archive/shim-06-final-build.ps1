$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

# 1. Run the PS-native shim generator (now resilient to wiped bin folder)
Write-Host "==> Running PS shim generator" -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\shims\generate-shims.ps1'
if ($LASTEXITCODE -ne 0) {
    Write-Error "Generator failed"
    exit 1
}

# 2. Build all 4 shims
Write-Host ""
Write-Host "==> Building shim projects" -ForegroundColor Cyan
$shims = @('Bannerlord.Harmony.Shim','Bannerlord.ButterLib.Shim','Bannerlord.UIExtenderEx.Shim','MCMv5.Shim')
$results = [ordered]@{}
foreach ($s in $shims) {
    Write-Host ""
    Write-Host "==== $s ====" -ForegroundColor Cyan
    $proj = "C:\dev\bannerlord\crest\shims\$s\$s.csproj"
    Push-Location "C:\dev\bannerlord\crest\shims\$s"
    try {
        $output = & dotnet build $proj -c Release --nologo -v minimal 2>&1
        $exit = $LASTEXITCODE
        if ($exit -eq 0) {
            $output | Where-Object { $_ -match 'Build succeeded' } | Select-Object -First 1 | ForEach-Object {
                Write-Host "  $_" -ForegroundColor Green
            }
            $expectedAsmName = $s.Replace('.Shim','')
            $outDll = Get-ChildItem -Recurse -Filter "$expectedAsmName.dll" -Path "bin\Release" -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($outDll) {
                Write-Host ("    -> {0,9:N0}B  {1}" -f $outDll.Length, $outDll.FullName) -ForegroundColor Green
            }
            $results[$s] = $true
        } else {
            Write-Host "  FAIL (exit $exit) - first 12 errors:" -ForegroundColor Red
            $output | Where-Object { $_ -match 'error ' } | Select-Object -First 12 | ForEach-Object {
                Write-Host "    $_" -ForegroundColor Red
            }
            $results[$s] = $false
        }
    } finally { Pop-Location }
}

Write-Host ""
Write-Host "==== Summary ====" -ForegroundColor Cyan
foreach ($k in $results.Keys) {
    $color = if ($results[$k]) { 'Green' } else { 'Red' }
    $status = if ($results[$k]) { 'OK' } else { 'FAIL' }
    Write-Host ("  {0,-30} {1}" -f $k, $status) -ForegroundColor $color
}
