$ErrorActionPreference = 'Continue'

Write-Host "==> Phase H: build all 4 compatibility shim projects" -ForegroundColor Cyan

$shimRoot = 'C:\dev\bannerlord\crest\shims'
$shims = @(
    'Bannerlord.Harmony.Shim',
    'Bannerlord.ButterLib.Shim',
    'Bannerlord.UIExtenderEx.Shim',
    'MCMv5.Shim'
)

$results = [ordered]@{}
foreach ($s in $shims) {
    Write-Host ""
    Write-Host "==== $s ====" -ForegroundColor Cyan
    $proj = Join-Path $shimRoot "$s\$s.csproj"
    if (-not (Test-Path $proj)) {
        Write-Host "  csproj missing: $proj" -ForegroundColor Red
        $results[$s] = $false
        continue
    }
    Push-Location (Join-Path $shimRoot $s)
    try {
        # Quiet first attempt; if it fails we re-run loud
        $output = & dotnet build $proj -c Release --nologo -v quiet 2>&1
        $exit = $LASTEXITCODE
        if ($exit -eq 0) {
            $output | Where-Object { $_ -match 'Build succeeded' } | Select-Object -First 1 | ForEach-Object {
                Write-Host "  OK - $_" -ForegroundColor Green
            }
            # Find the produced DLL
            $outDll = Get-ChildItem -Recurse -Filter "*.dll" -Path "bin\Release" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch '\.Shim\.dll$' } |
                Select-Object -First 1
            if ($outDll) {
                Write-Host ("  produced: {0,9:N0}B  {1}" -f $outDll.Length, $outDll.FullName) -ForegroundColor Green
            }
            $results[$s] = $true
        } else {
            Write-Host "  FAIL (exit $exit) - showing errors:" -ForegroundColor Red
            $output | Where-Object { $_ -match 'error |Build FAILED' } | Select-Object -First 15 | ForEach-Object {
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
