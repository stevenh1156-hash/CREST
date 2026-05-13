# MCM step 4: fix any remaining stale path refs (folder names in csproj/sln)
# that bulk replace missed because they don't have a dot suffix.
# Then update test namespaces, then build.
$ErrorActionPreference = 'Continue'
$gameFolder = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'

$repoRoot = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen'
cd $repoRoot

# 1. Fix folder path refs in csproj/sln (e.g. `src\MCM\` -> `src\Crest.MCM\`).
# Map old folder name -> new folder name. Order matters: longer names first so
# `MCM.UI.Adapter.MCMv5` rewrites before `MCM.UI`, and so on.
$folderMap = @(
    @{Old='MCM.UI.Adapter.MCMv5';  New='Crest.MCM.UI.Adapter.MCMv5'},
    @{Old='MCM.Abstractions';      New='Crest.MCM.Abstractions'},
    @{Old='MCM.Implementation';    New='Crest.MCM.Implementation'},
    @{Old='MCM.Bannerlord';        New='Crest.MCM.Bannerlord'},
    @{Old='MCM.Common';            New='Crest.MCM.Common'},
    @{Old='MCM.Source';            New='Crest.MCM.Source'},
    @{Old='MCM.UI';                New='Crest.MCM.UI'},
    @{Old='MCM.UnitTests';         New='Crest.MCM.UnitTests'},
    @{Old='MCMv5.Tests';           New='Crest.MCM.Tests'},
    @{Old='MCM';                   New='Crest.MCM'}
)

$projfiles = Get-ChildItem -Recurse -File -Path $repoRoot -Include *.csproj,*.sln |
    Where-Object { $_.FullName -notlike '*\bin\*' -and $_.FullName -notlike '*\obj\*' }

$changed = 0
foreach ($f in $projfiles) {
    $content = [System.IO.File]::ReadAllText($f.FullName)
    $orig = $content
    foreach ($m in $folderMap) {
        # Match `\<OldName>\` or `\<OldName>"` (path separators or quote).
        # Negative lookbehind for `Crest.` so we don't double-prefix.
        $pat = '(?<!Crest\.)(?<![\w.])' + [regex]::Escape($m.Old) + '(?=[\\""])'
        $content = [regex]::Replace($content, $pat, $m.New)
    }
    if ($content -ne $orig) {
        [System.IO.File]::WriteAllText($f.FullName, $content)
        $changed++
        Write-Host "    fixed paths in: $($f.Name)"
    }
}
Write-Host "==> Path fixes: $changed of $($projfiles.Count) project files"

# 2. Update MCMv5.Tests namespaces to Crest.MCM.Tests (cosmetic)
$testFiles = Get-ChildItem -Recurse -File -Path $repoRoot\tests -Include *.cs |
    Where-Object { $_.FullName -notlike '*\bin\*' -and $_.FullName -notlike '*\obj\*' }
$tn = 0
foreach ($f in $testFiles) {
    $content = [System.IO.File]::ReadAllText($f.FullName)
    $orig = $content
    $content = $content -replace 'MCMv5\.Tests', 'Crest.MCM.Tests'
    if ($content -ne $orig) {
        [System.IO.File]::WriteAllText($f.FullName, $content)
        $tn++
    }
}
Write-Host "==> Test namespace fixes: $tn"

# 3. Build main MCM
Write-Host ""
Write-Host "==> Building Crest.MCM (main)..." -ForegroundColor Cyan
dotnet build src/Crest.MCM/Crest.MCM.csproj --configuration Release `
    -p:GameFolder=$gameFolder `
    -p:OverrideGameVersion=v1.4.1 -p:GameVersionConstant=v141 `
    -p:GenerateDocumentationFile=false -nowarn:CS1591 `
    --nologo -v quiet 2>&1 | Select-String -Pattern 'error |FAIL|Build succeeded|Errors' | ForEach-Object { Write-Host "    $_" }
$mainCode = $LASTEXITCODE
Write-Host "    main exit: $mainCode"

# 4. Build UI
Write-Host ""
Write-Host "==> Building Crest.MCM.UI..." -ForegroundColor Cyan
dotnet build src-ui/Crest.MCM.UI/Crest.MCM.UI.csproj --configuration Stable_Release `
    -p:GameFolder=$gameFolder `
    -p:OverrideGameVersion=v1.4.1 -p:GameVersionConstant=v141 `
    -p:GenerateDocumentationFile=false -nowarn:CS1591 -p:ExtendedBuild=false `
    --nologo -v quiet 2>&1 | Select-String -Pattern 'error |FAIL|Build succeeded|Errors' | ForEach-Object { Write-Host "    $_" }
$uiCode = $LASTEXITCODE
Write-Host "    ui exit: $uiCode"

Write-Host ""
Write-Host "==> Output DLLs:"
Get-ChildItem src\Crest.MCM\bin\Release -Recurse -Filter Crest.MCM.dll -ErrorAction SilentlyContinue | ForEach-Object {
    $age = ((Get-Date) - $_.LastWriteTime).TotalSeconds
    Write-Host ("    {0:N1}KB  {1:N0}s old  {2}" -f ($_.Length/1KB), $age, $_.FullName)
}
Get-ChildItem src-ui\Crest.MCM.UI\bin -Recurse -Filter Crest.MCM.UI.dll -ErrorAction SilentlyContinue | ForEach-Object {
    $age = ((Get-Date) - $_.LastWriteTime).TotalSeconds
    Write-Host ("    {0:N1}KB  {1:N0}s old  {2}" -f ($_.Length/1KB), $age, $_.FullName)
}

if ($mainCode -eq 0 -and $uiCode -eq 0) {
    Write-Host ""
    Write-Host "==> Both green. Committing..." -ForegroundColor Green
    git add -A
    git commit -m "chore(crest): rebrand Bannerlord.MBOptionScreen to Crest.MCM

- Rename src/MCM/ and 5 source-included subprojects to Crest.MCM.*
- Rename src-ui/MCM.UI/ and Adapter project to Crest.MCM.UI.*
- Rename Mod Configuration Menu.sln to Crest.MCM.sln
- Rename tests/MCMv5.Tests/ to tests/Crest.MCM.Tests/
- Rename tests/MCM.UnitTests/ to tests/Crest.MCM.UnitTests/
- Set AssemblyName=Crest.MCM (was MCMv5), RootNamespace=Crest.MCM
- Set PackageId=Crest.MCM (was Bannerlord.MCM)
- Set ModuleId=CREST (was Bannerlord.MBOptionScreen)
- Set ModuleName='CREST MCM' (was 'Mod Configuration Menu v5')
- Bulk replace C# namespaces, usings, and type refs from MCM.* to Crest.MCM.*
- Fix bare 'namespace MCM' declarations (no dot suffix)
- Fix path references in csproj/sln files
- Update test namespaces from MCMv5.Tests to Crest.MCM.Tests"
    git log --oneline -1
} else {
    Write-Host ""
    Write-Host "==> Build failed. Not committing." -ForegroundColor Red
}

exit 0
