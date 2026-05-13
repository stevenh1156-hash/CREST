$ErrorActionPreference = 'Continue'

Write-Host '==> Test 1: full doctor (no args, runs all checks)' -ForegroundColor Cyan
$reportFull = 'C:\dev\bannerlord\crest\dist\doctor-full.md'
& 'C:\dev\bannerlord\crest\tools\doctor\Crest-Doctor.ps1' -ReportPath $reportFull

Write-Host ''
Write-Host '==> Test 2: focused mod check on BloodMod1313' -ForegroundColor Cyan
$reportMod = 'C:\dev\bannerlord\crest\dist\doctor-bloodmod.md'
& 'C:\dev\bannerlord\crest\tools\doctor\Crest-Doctor.ps1' -Mod 'BloodMod1313' -ReportPath $reportMod

Write-Host ''
Write-Host '==> Reports written:' -ForegroundColor Green
Write-Host ('   ' + $reportFull)
Write-Host ('   ' + $reportMod)
