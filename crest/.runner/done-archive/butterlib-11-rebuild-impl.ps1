$ErrorActionPreference = 'Continue'
$gameFolder = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'

cd C:\dev\bannerlord\Bannerlord.ButterLib

Write-Host "==> Rebuild Crest.ButterLib (main, refresh InternalsVisibleTo)..." -ForegroundColor Cyan
dotnet build src/Crest.ButterLib/Crest.ButterLib.csproj --configuration Release -p:GameFolder=$gameFolder -p:OverrideGameVersion=v1.4.1 -p:GameVersionConstant=v141 -p:GenerateDocumentationFile=false -nowarn:CS1591 --nologo -v quiet 2>&1 | Select-String -Pattern 'error |FAIL|Build succeeded|Errors' | ForEach-Object { Write-Host "    $_" }
$mainCode = $LASTEXITCODE
Write-Host "    main exit: $mainCode"

Write-Host ""
Write-Host "==> Build Crest.ButterLib.Implementation..." -ForegroundColor Cyan
dotnet build src/Crest.ButterLib.Implementation/Crest.ButterLib.Implementation.csproj --configuration Stable_Release -p:GameFolder=$gameFolder -p:OverrideGameVersion=v1.4.1 -p:GameVersionConstant=v141 -p:GenerateDocumentationFile=false -nowarn:CS1591 --nologo -v quiet 2>&1 | Select-String -Pattern 'error |FAIL|Build succeeded|Errors' | ForEach-Object { Write-Host "    $_" }
$implCode = $LASTEXITCODE
Write-Host "    impl exit: $implCode"

Write-Host ""
Write-Host "==> DLLs produced:" -ForegroundColor Cyan
Get-ChildItem src\Crest.ButterLib\bin\Release -Recurse -Filter Crest.ButterLib.dll -ErrorAction SilentlyContinue | ForEach-Object {
    $age = ((Get-Date) - $_.LastWriteTime).TotalSeconds
    Write-Host ("    {0:N1}KB  {1:N0}s old  {2}" -f ($_.Length/1KB), $age, $_.FullName)
}
Get-ChildItem src\Crest.ButterLib.Implementation\bin -Recurse -Filter Crest.ButterLib.Implementation.dll -ErrorAction SilentlyContinue | ForEach-Object {
    $age = ((Get-Date) - $_.LastWriteTime).TotalSeconds
    Write-Host ("    {0:N1}KB  {1:N0}s old  {2}" -f ($_.Length/1KB), $age, $_.FullName)
}

if ($mainCode -eq 0 -and $implCode -eq 0) {
    Write-Host ""
    Write-Host "==> Both green. Committing..." -ForegroundColor Green
    git add -A
    git commit -m "chore(crest): rebrand Bannerlord.ButterLib to Crest.ButterLib

- Rename src/Bannerlord.ButterLib/ to src/Crest.ButterLib/ (main facade)
- Rename src/Bannerlord.ButterLib.Implementation/ to src/Crest.ButterLib.Implementation/
- Rename Bannerlord.ButterLib.sln to Crest.ButterLib.sln
- Rename four test projects to Crest.ButterLib.* equivalents
- Set AssemblyName/RootNamespace explicitly on both production projects
- Drop game-version suffix from Implementation AssemblyName
- Set ModuleId=CREST, ModuleName='CREST ButterLib'
- Set PackageId=Crest.ButterLib
- Bulk replace C# namespaces and usings across 147 files
- Fully qualify Bannerlord.BUTR.Shared.* relative refs that broke after ns rename
- Add InternalsVisibleTo for Crest.ButterLib.Implementation (no version suffix)
- Update StacktraceFilter runtime ID checks to 'CREST'
- Update InternalsVisibleTo to point at renamed test projects"
    git log --oneline -1
} else {
    Write-Host ""
    Write-Host "==> Build still failing. Not committing." -ForegroundColor Red
}

exit 0
