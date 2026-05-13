$ErrorActionPreference = 'Continue'
Set-Location 'C:\dev\bannerlord\Bannerlord.Harmony'
$out = 'C:\dev\bannerlord\crest\.runner\done\harmony-build-detail.log'
Write-Host "==> Building Crest.Harmony with full output -> $out" -ForegroundColor Cyan
& dotnet build src/Crest.Harmony/Crest.Harmony.csproj -c Release -v normal --nologo 2>&1 | Tee-Object -FilePath $out | Out-Null
Write-Host ("    exit code: " + $LASTEXITCODE)
Write-Host ""
Write-Host "==> Last 60 lines of build output:" -ForegroundColor Cyan
Get-Content $out -Tail 60
exit 0
