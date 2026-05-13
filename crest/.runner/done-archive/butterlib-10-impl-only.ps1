# Focused build of Implementation only, with quieter output, to see the actual errors.
$ErrorActionPreference = 'Continue'
$gameFolder = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'

cd C:\dev\bannerlord\Bannerlord.ButterLib

Write-Host "==> Building ONLY Crest.ButterLib.Implementation..." -ForegroundColor Cyan
# Use /p:GenerateDocumentationFile=false to suppress XML doc warnings,
# and /p:TreatWarningsAsErrors=false. -nowarn:CS1591 to silence missing-doc warnings specifically.
dotnet build src/Crest.ButterLib.Implementation/Crest.ButterLib.Implementation.csproj `
    --configuration Stable_Release `
    -p:GameFolder=$gameFolder `
    -p:OverrideGameVersion=v1.4.1 `
    -p:GameVersionConstant=v141 `
    -p:GenerateDocumentationFile=false `
    -nowarn:CS1591 `
    --nologo `
    -v normal 2>&1 | Select-String -Pattern 'error|FAIL|succeeded|^Build|Errors|warning(?! CS1591)' | ForEach-Object { Write-Host $_ }

Write-Host ""
Write-Host "==> Implementation exit code: $LASTEXITCODE"
exit 0
