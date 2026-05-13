$ErrorActionPreference = 'Continue'

# Clean up the bogus literal-name directory the bash run created
$bogus = 'C:\dev\bannerlord\crest\shims\C:\dev\bannerlord'
if (Test-Path $bogus) {
    Write-Host "==> Cleaning up bogus path tree"
    Remove-Item -Recurse -Force $bogus
}

# Re-run the Python generator using a path system that works on Windows
Write-Host "==> Re-running generate-shims.py"
Push-Location 'C:\dev\bannerlord\crest\shims'
try {
    & python generate-shims.py 2>&1 | ForEach-Object { Write-Host "  $_" }
} finally { Pop-Location }

Write-Host ""
Write-Host "==> Final shim folder tree:"
Get-ChildItem -Recurse -Path 'C:\dev\bannerlord\crest\shims' -File |
    Where-Object { $_.FullName -notlike '*\bin\*' -and $_.FullName -notlike '*\obj\*' } |
    ForEach-Object { Write-Host ("    {0,7:N0}B  {1}" -f $_.Length, $_.FullName.Replace('C:\dev\bannerlord\crest\shims\', '')) }
