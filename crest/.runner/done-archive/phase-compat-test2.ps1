$ErrorActionPreference = 'Continue'

Write-Host '==> Crest-Doctor with first-party-module exclusion fix' -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\tools\doctor\Crest-Doctor.ps1' -Compat

Write-Host ''
Write-Host '==> Crest-Compat dry-run with same fix' -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\tools\compat\Crest-Compat.ps1'
