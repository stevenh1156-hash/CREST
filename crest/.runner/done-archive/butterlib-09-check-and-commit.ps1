# Check whether builds produced fresh DLLs, then commit if so.
$ErrorActionPreference = 'Continue'

cd C:\dev\bannerlord\Bannerlord.ButterLib

$mainDll = Get-ChildItem src\Crest.ButterLib\bin\Release -Recurse -Filter Crest.ButterLib.dll -ErrorAction SilentlyContinue | Select-Object -First 1
$implDll = Get-ChildItem src\Crest.ButterLib.Implementation\bin -Recurse -Filter Crest.ButterLib.Implementation*.dll -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '*.deps.json' } | Select-Object -First 1

Write-Host "==> DLL artifact check:"
if ($mainDll) {
    $age = (Get-Date) - $mainDll.LastWriteTime
    Write-Host ("    main: {0}  ({1:N1}KB, {2:N0}s old)" -f $mainDll.FullName, ($mainDll.Length/1KB), $age.TotalSeconds)
} else {
    Write-Host "    main: NOT FOUND" -ForegroundColor Red
}
if ($implDll) {
    $age = (Get-Date) - $implDll.LastWriteTime
    Write-Host ("    impl: {0}  ({1:N1}KB, {2:N0}s old)" -f $implDll.FullName, ($implDll.Length/1KB), $age.TotalSeconds)
} else {
    Write-Host "    impl: NOT FOUND" -ForegroundColor Red
}

if ($mainDll -and $implDll) {
    # Both DLLs present and presumably fresh. Commit.
    Write-Host ""
    Write-Host "==> Both DLLs present. Committing..." -ForegroundColor Green
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
- Update StacktraceFilter runtime ID checks to 'CREST'
- Update InternalsVisibleTo to point at renamed test projects"
    git log --oneline -1
} else {
    Write-Host ""
    Write-Host "==> Build artifacts missing. Not committing." -ForegroundColor Red
}

exit 0
