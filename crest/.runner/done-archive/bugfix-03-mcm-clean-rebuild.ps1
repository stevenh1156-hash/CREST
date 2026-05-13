# Clean MCM.UI bin/obj (stale artifacts from before AssemblyName=Crest.MCM.UI was set), then rebuild.
$ErrorActionPreference = 'Continue'
$gameFolder = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'

cd C:\dev\bannerlord\Bannerlord.MBOptionScreen

# Clean bin/obj across all renamed projects
Write-Host "==> Cleaning bin/obj across MCM repo..." -ForegroundColor Cyan
$cleaned = 0
Get-ChildItem -Recurse -Directory -Path src,src-ui -Filter bin -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item -Recurse -Force $_.FullName -ErrorAction SilentlyContinue
    $cleaned++
}
Get-ChildItem -Recurse -Directory -Path src,src-ui -Filter obj -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item -Recurse -Force $_.FullName -ErrorAction SilentlyContinue
    $cleaned++
}
Write-Host "    cleaned $cleaned bin/obj folders"

Write-Host "`n==> Rebuilding Crest.MCM..." -ForegroundColor Cyan
dotnet build src/Crest.MCM/Crest.MCM.csproj --configuration Release `
    -p:GameFolder=$gameFolder -p:OverrideGameVersion=v1.4.1 -p:GameVersionConstant=v141 `
    -p:GenerateDocumentationFile=false -nowarn:CS1591 `
    --nologo -v quiet 2>&1 | Select-String -Pattern 'error |FAIL|Build succeeded|Errors' | ForEach-Object { Write-Host "    $_" }
$mainCode = $LASTEXITCODE
Write-Host "    main exit: $mainCode"

Write-Host "`n==> Rebuilding Crest.MCM.UI..." -ForegroundColor Cyan
dotnet build src-ui/Crest.MCM.UI/Crest.MCM.UI.csproj --configuration Stable_Release `
    -p:GameFolder=$gameFolder -p:OverrideGameVersion=v1.4.1 -p:GameVersionConstant=v141 `
    -p:GenerateDocumentationFile=false -nowarn:CS1591 -p:ExtendedBuild=false `
    --nologo -v quiet 2>&1 | Select-String -Pattern 'error |FAIL|Build succeeded|Errors' | ForEach-Object { Write-Host "    $_" }
$uiCode = $LASTEXITCODE
Write-Host "    ui exit: $uiCode"

Write-Host "`n==> Output DLLs after rebuild:" -ForegroundColor Cyan
Get-ChildItem -Recurse -Path src,src-ui -Filter '*.dll' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notlike '*\obj\*' } | ForEach-Object {
        Write-Host ("    {0:N1}KB  {1}" -f ($_.Length/1KB), $_.FullName.Replace('C:\dev\bannerlord\Bannerlord.MBOptionScreen\',''))
    }

if ($mainCode -eq 0 -and $uiCode -eq 0) {
    Write-Host "`n==> Both green." -ForegroundColor Green
} else {
    Write-Host "`n==> BUILD FAILED" -ForegroundColor Red
}
exit 0
