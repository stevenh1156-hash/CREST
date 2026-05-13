$ErrorActionPreference = 'Continue'

Write-Host "==> Phase H: build all 4 compatibility shim projects" -ForegroundColor Cyan

$shimRoot = 'C:\dev\bannerlord\crest\shims'
$shims = @(
    'Bannerlord.Harmony.Shim',
    'Bannerlord.ButterLib.Shim',
    'Bannerlord.UIExtenderEx.Shim',
    'MCMv5.Shim'
)

# Verify shim files are now in place
Write-Host "==> Verifying shim project structure:"
foreach ($s in $shims) {
    $proj = Join-Path $shimRoot "$s\$s.csproj"
    $cs   = Join-Path $shimRoot "$s\TypeForwarders.cs"
    Write-Host ("    {0,-30} csproj={1}  cs={2}" -f $s, (Test-Path $proj), (Test-Path $cs))
}

$results = [ordered]@{}
foreach ($s in $shims) {
    Write-Host ""
    Write-Host "==== $s ====" -ForegroundColor Cyan
    $proj = Join-Path $shimRoot "$s\$s.csproj"
    Push-Location (Join-Path $shimRoot $s)
    try {
        Write-Host "  dotnet build (loud first time so we see errors)" -ForegroundColor DarkGray
        $output = & dotnet build $proj -c Release --nologo -v minimal 2>&1
        $exit = $LASTEXITCODE
        if ($exit -eq 0) {
            $output | Where-Object { $_ -match 'Build succeeded|Warnings|Errors' } | Select-Object -First 5 | ForEach-Object {
                Write-Host "    $_" -ForegroundColor Green
            }
            $outDll = Get-ChildItem -Recurse -Filter "*.dll" -Path "bin\Release" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch '\.Shim\.dll$' -and $_.Name -notmatch 'Crest\.' } |
                Select-Object -First 1
            if ($outDll) {
                Write-Host ("    -> {0,9:N0}B  {1}" -f $outDll.Length, $outDll.FullName) -ForegroundColor Green
            }
            $results[$s] = $true
        } else {
            Write-Host "  FAIL (exit $exit) - first 25 lines of output:" -ForegroundColor Red
            $output | Select-Object -First 25 | ForEach-Object {
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
