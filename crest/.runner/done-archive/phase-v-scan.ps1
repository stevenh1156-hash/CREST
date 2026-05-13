$ErrorActionPreference = 'Stop'
$report = 'C:\dev\bannerlord\crest\v142-compat-report.md'
& powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\dev\bannerlord\crest\tools\v142-compat\Crest-V142Compat.ps1' -ReportPath $report
exit 0
