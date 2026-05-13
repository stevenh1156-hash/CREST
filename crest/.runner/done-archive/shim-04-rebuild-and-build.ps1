$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

# Step 1: rebuild Crest.MCM with BANNERLORDMCM_NOT_SOURCE removed
Write-Host "==> Rebuilding Crest.MCM (no _NOT_SOURCE - more public types)" -ForegroundColor Cyan
$ok = Build-CrestRepo -Name 'MCM' -Clean
if (-not $ok) { Write-Error "MCM build failed"; exit 1 }

# Step 2: re-bundle (so deployed Crest.MCM.dll matches the rebuilt one)
Write-Host ""
Write-Host "==> Re-bundle (deployed Crest.MCM.dll has the wider public surface)" -ForegroundColor Cyan
$ok = Build-CrestBundle -SkipBuild -Version '1.0.0'
if (-not $ok) { exit 2 }
$ok = Deploy-CrestToBannerlord
if (-not $ok) { exit 3 }

# Step 3: re-run the shim generator using py launcher (Windows path-aware)
Write-Host ""
Write-Host "==> Re-running shim generator" -ForegroundColor Cyan
Push-Location 'C:\dev\bannerlord\crest\shims'
try {
    & py generate-shims.py 2>&1 | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  py launcher failed - trying python3.exe via full path" -ForegroundColor Yellow
        # Look for python in common install locations
        $candidates = @(
            'C:\Python313\python.exe',
            'C:\Python312\python.exe',
            'C:\Python311\python.exe',
            'C:\Python310\python.exe',
            'C:\Python39\python.exe',
            "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
            "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
            "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe"
        )
        $py = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($py) {
            Write-Host "  using $py" -ForegroundColor Yellow
            & $py generate-shims.py 2>&1 | ForEach-Object { Write-Host "  $_" }
        }
    }
} finally { Pop-Location }

# Step 4: try shim builds
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
            # Find produced output DLL (the one matching the AssemblyName, not Crest.* deps)
            $expectedAsmName = $s.Replace('.Shim','')
            $outDll = Get-ChildItem -Recurse -Filter "$expectedAsmName.dll" -Path "bin\Release" -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($outDll) {
                Write-Host ("    -> {0,9:N0}B  {1}" -f $outDll.Length, $outDll.FullName) -ForegroundColor Green
            } else {
                Write-Host "    (output dll not found at expected name $expectedAsmName.dll)" -ForegroundColor Yellow
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
