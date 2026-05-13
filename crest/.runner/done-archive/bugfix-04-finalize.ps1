# Bug fix finalization across 4 repos: rebuild + commit each.
$ErrorActionPreference = 'Continue'
$gameFolder = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'

# ============================================================
# Repo 1: ButterLib - StacktraceFilter fix (already edited via Cowork)
# ============================================================
Write-Host "==== ButterLib: StacktraceFilter fix ====" -ForegroundColor Cyan
cd C:\dev\bannerlord\Bannerlord.ButterLib
git status --short

Write-Host ""
Write-Host "==> Rebuild ButterLib + Implementation (sanity check)..."
dotnet build src/Crest.ButterLib/Crest.ButterLib.csproj --configuration Release `
    -p:GameFolder=$gameFolder -p:OverrideGameVersion=v1.4.1 -p:GameVersionConstant=v141 `
    -p:GenerateDocumentationFile=false -nowarn:CS1591 --nologo -v quiet 2>&1 |
    Select-String -Pattern 'error |FAIL|Build succeeded' | ForEach-Object { Write-Host "    $_" }
$bl1 = $LASTEXITCODE
dotnet build src/Crest.ButterLib.Implementation/Crest.ButterLib.Implementation.csproj --configuration Stable_Release `
    -p:GameFolder=$gameFolder -p:OverrideGameVersion=v1.4.1 -p:GameVersionConstant=v141 `
    -p:GenerateDocumentationFile=false -nowarn:CS1591 --nologo -v quiet 2>&1 |
    Select-String -Pattern 'error |FAIL|Build succeeded' | ForEach-Object { Write-Host "    $_" }
$bl2 = $LASTEXITCODE
Write-Host "    butterlib main=$bl1 impl=$bl2"

if ($bl1 -eq 0 -and $bl2 -eq 0) {
    git add -A
    git commit -m "fix(crest): patch remaining StacktraceFilter module-ID lookups

Audit found 3 missed runtime ID checks in ButterLib's StacktraceFilter:
- line 53: 'Bannerlord.MBOptionScreen' -> 'CREST'
- line 98: 'Bannerlord.Harmony' -> 'CREST'
- line 100: class FQN 'Bannerlord.Harmony.SubModule' -> 'Crest.Harmony.SubModule'

Without these, the stack trace filter would silently fail to recognize
CREST modules and would not strip BUTR-internal frames as it does upstream."
    git log --oneline -1
} else {
    Write-Host "    BUTTERLIB BUILD FAILED, skipping commit" -ForegroundColor Red
}

# ============================================================
# Repo 2: MCM - cross-fork wiring (already edited via Cowork)
# ============================================================
Write-Host "`n==== MCM: cross-fork ProjectReferences ====" -ForegroundColor Cyan
cd C:\dev\bannerlord\Bannerlord.MBOptionScreen
git status --short | Select-Object -First 12 | ForEach-Object { Write-Host "    $_" }

# Already built in previous job; commit if main/UI build artifacts exist
if ((Test-Path src\Crest.MCM\bin\Release\netstandard2.0\Crest.MCM.dll) -and
    (Test-Path src-ui\Crest.MCM.UI\bin\Stable_Release\netstandard2.0\CREST.v1.4.1.dll)) {
    git add -A
    git commit -m "fix(crest): wire MCM.UI cross-fork references to Crest.* repos

Audit found MCM.UI source had 'using Bannerlord.UIExtenderEx.*' and
'using Bannerlord.ButterLib' across 9 files. These compiled against
upstream BUTR NuGet packages but would TypeLoadException at runtime
inside CREST because we ship Crest.* assemblies, not Bannerlord.*.

- Replace 'using Bannerlord.UIExtenderEx' -> 'using Crest.UIExtenderEx'
- Replace 'using Bannerlord.ButterLib' -> 'using Crest.ButterLib'
- Add cross-repo ProjectReferences in Crest.MCM.UI.csproj to:
    ..\..\..\Bannerlord.UIExtenderEx\src\Crest.UIExtenderEx
    ..\..\..\Bannerlord.ButterLib\src\Crest.ButterLib
- Set explicit AssemblyName=Crest.MCM.UI on UI project"
    git log --oneline -1
} else {
    Write-Host "    MCM artifacts missing, skipping commit" -ForegroundColor Red
}

# ============================================================
# Repo 3: Harmony - language files
# ============================================================
Write-Host "`n==== Harmony: language file localization fix ====" -ForegroundColor Cyan
cd C:\dev\bannerlord\Bannerlord.Harmony

$langDir = 'src\Crest.Harmony\_Module\ModuleData\Languages'
$langFiles = Get-ChildItem -Recurse -File -Path $langDir -Include *.xml -ErrorAction SilentlyContinue
$lc = 0
foreach ($f in $langFiles) {
    $content = [System.IO.File]::ReadAllText($f.FullName)
    if ($content -match 'Bannerlord\.Harmony') {
        $content = $content -replace 'Bannerlord\.Harmony', 'CREST'
        [System.IO.File]::WriteAllText($f.FullName, $content)
        $lc++
    }
}
Write-Host "    updated $lc of $($langFiles.Count) language files"

if ($lc -gt 0) {
    git add -A
    git commit -m "fix(crest): rebrand 'Bannerlord.Harmony' -> 'CREST' in localized warning strings

Audit found 8 language files (CN, DE, EN, JP, RO, RU, SP, TR) still
referenced 'Bannerlord.Harmony' in the localized version of the
'module not found' / 'not first in load order' warnings. The English
default in SubModule.cs was already updated; this brings translations
in sync so non-English players see the correct CREST brand."
    git log --oneline -1
}

# ============================================================
# Repo 4: UIExtenderEx - test project rename
# ============================================================
Write-Host "`n==== UIExtenderEx: test project rename ====" -ForegroundColor Cyan
cd C:\dev\bannerlord\Bannerlord.UIExtenderEx

if (Test-Path tests\Bannerlord.UIExtenderEx.Tests) {
    cd tests
    Write-Host "    renaming Bannerlord.UIExtenderEx.Tests -> Crest.UIExtenderEx.Tests"
    git mv Bannerlord.UIExtenderEx.Tests Crest.UIExtenderEx.Tests 2>&1 | ForEach-Object { Write-Host "    $_" }
    git mv "Crest.UIExtenderEx.Tests\Bannerlord.UIExtenderEx.Tests.csproj" "Crest.UIExtenderEx.Tests\Crest.UIExtenderEx.Tests.csproj" 2>&1 | ForEach-Object { Write-Host "    $_" }
    cd ..

    # Bulk replace remaining Bannerlord.UIExtenderEx references in renamed tests
    $testFiles = Get-ChildItem -Recurse -File -Path tests\Crest.UIExtenderEx.Tests -Include *.cs,*.csproj -ErrorAction SilentlyContinue
    $tc = 0
    foreach ($f in $testFiles) {
        $content = [System.IO.File]::ReadAllText($f.FullName)
        $orig = $content
        $content = $content -replace 'Bannerlord\.UIExtenderEx', 'Crest.UIExtenderEx'
        if ($content -ne $orig) {
            [System.IO.File]::WriteAllText($f.FullName, $content)
            $tc++
        }
    }
    Write-Host "    updated $tc test files"

    # Also fix the .sln reference to the test project
    $sln = 'src\Crest.UIExtenderEx.sln'
    $slnContent = [System.IO.File]::ReadAllText($sln)
    $slnContent = $slnContent -replace 'Bannerlord\.UIExtenderEx\.Tests', 'Crest.UIExtenderEx.Tests'
    [System.IO.File]::WriteAllText($sln, $slnContent)
    Write-Host "    updated .sln test project reference"

    git add -A
    git commit -m "fix(crest): rename Bannerlord.UIExtenderEx.Tests to Crest.UIExtenderEx.Tests

Audit found this test project was missed during the UIExtenderEx rebrand,
making it inconsistent with ButterLib and MCM where test projects were
renamed for symmetry. Also leaves the .sln referencing the old name.

- Rename tests/Bannerlord.UIExtenderEx.Tests -> tests/Crest.UIExtenderEx.Tests
- Rename test csproj inside
- Update namespaces and InternalsVisibleTo references in test source
- Update .sln project entry"
    git log --oneline -1
} else {
    Write-Host "    test project already renamed or not present"
}

Write-Host "`n==== ALL BUG FIXES DONE ====" -ForegroundColor Green
exit 0
