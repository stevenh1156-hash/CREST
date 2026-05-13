# ButterLib step 3: build both projects, commit if green.
$ErrorActionPreference = 'Continue'
$gameFolder = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'

cd C:\dev\bannerlord\Bannerlord.ButterLib

Write-Host "==> Building Crest.ButterLib (main facade, Release)..." -ForegroundColor Cyan
dotnet build src/Crest.ButterLib/Crest.ButterLib.csproj --configuration Release -p:GameFolder=$gameFolder -p:OverrideGameVersion=v1.4.1 -p:GameVersionConstant=v141
$mainCode = $LASTEXITCODE

Write-Host "`n==> Building Crest.ButterLib.Implementation (Stable_Release)..." -ForegroundColor Cyan
dotnet build src/Crest.ButterLib.Implementation/Crest.ButterLib.Implementation.csproj --configuration Stable_Release -p:GameFolder=$gameFolder -p:OverrideGameVersion=v1.4.1 -p:GameVersionConstant=v141
$implCode = $LASTEXITCODE

Write-Host "`n==> Build summary:"
Write-Host "    Crest.ButterLib                main   exit=$mainCode"
Write-Host "    Crest.ButterLib.Implementation impl   exit=$implCode"

if ($mainCode -eq 0 -and $implCode -eq 0) {
    Write-Host "`n==> Output DLLs:" -ForegroundColor Green
    Get-ChildItem src\Crest.ButterLib\bin\Release\**\Crest.ButterLib.dll -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "    $([math]::Round($_.Length/1KB,1))KB  $($_.FullName)"
    }
    Get-ChildItem src\Crest.ButterLib.Implementation\bin\**\*\Crest.ButterLib.Implementation*.dll -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "    $([math]::Round($_.Length/1KB,1))KB  $($_.FullName)"
    }

    Write-Host "`n==> Committing ButterLib rebrand..." -ForegroundColor Cyan
    git add -A
    git commit -m "chore(crest): rebrand Bannerlord.ButterLib to Crest.ButterLib

- Rename src/Bannerlord.ButterLib/ -> src/Crest.ButterLib/ (main facade)
- Rename src/Bannerlord.ButterLib.Implementation/ -> src/Crest.ButterLib.Implementation/
- Rename Bannerlord.ButterLib.sln -> Crest.ButterLib.sln
- Rename four test projects (Tests, Implementation.Tests, ObjectSystem.Test, HotKeys.Test)
- Set AssemblyName/RootNamespace explicitly on both production projects
- Drop game-version suffix from Implementation AssemblyName (Crest.ButterLib.Implementation.dll, no .v141)
- Set ModuleId=CREST, ModuleName='CREST ButterLib'
- Set PackageId=Crest.ButterLib
- Bulk replace C# namespaces and using statements across 147 files
- Update StacktraceFilter runtime ID checks: 'Bannerlord.Harmony' and 'Crest.ButterLib' both -> 'CREST'
- Update InternalsVisibleTo to point at renamed test projects"
    git log --oneline -1
} else {
    Write-Host "`n==> BUILD FAILED — not committing." -ForegroundColor Red
}

exit 0
