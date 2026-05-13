$ErrorActionPreference = 'Continue'

Write-Host '==> Test 1: Crest-Doctor with new Compatibility risks section' -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\tools\doctor\Crest-Doctor.ps1' -Compat

Write-Host ''
Write-Host '==> Test 2: Crest-Compat dry-run (no -Fix flag)' -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\tools\compat\Crest-Compat.ps1'
