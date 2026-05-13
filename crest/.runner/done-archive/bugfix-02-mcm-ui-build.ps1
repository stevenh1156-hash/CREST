# Verify MCM.UI builds with the new cross-fork ProjectReferences and Crest.* using statements.
$ErrorActionPreference = 'Continue'
$gameFolder = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'

cd C:\dev\bannerlord\Bannerlord.MBOptionScreen

Write-Host "==> Build MCM.UI..." -ForegroundColor Cyan
dotnet build src-ui/Crest.MCM.UI/Crest.MCM.UI.csproj --configuration Stable_Release `
    -p:GameFolder=$gameFolder `
    -p:OverrideGameVersion=v1.4.1 -p:GameVersionConstant=v141 `
    -p:GenerateDocumentationFile=false -nowarn:CS1591 -p:ExtendedBuild=false `
    --nologo -v normal 2>&1 | Select-String -Pattern 'error |FAIL|Build succeeded|Errors|Warnings' | ForEach-Object { Write-Host "    $_" }
$code = $LASTEXITCODE
Write-Host "    exit: $code"

Write-Host "`n==> Output DLLs:" -ForegroundColor Cyan
Get-ChildItem src-ui\Crest.MCM.UI\bin -Recurse -Filter Crest.MCM.UI.dll -ErrorAction SilentlyContinue | ForEach-Object {
    $age = ((Get-Date) - $_.LastWriteTime).TotalSeconds
    Write-Host ("    {0:N1}KB  {1:N0}s old  {2}" -f ($_.Length/1KB), $age, $_.FullName)
}
exit 0
