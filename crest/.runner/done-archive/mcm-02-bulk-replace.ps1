# MCM step 2: bulk find/replace in all renamed source.
# - `Bannerlord.MCM` -> `Crest.MCM` in all files (NuGet package ID, etc.)
# - `Bannerlord.MBOptionScreen` -> `CREST` (mod ID in template SubModule.xml etc.)
# - `(?<![\w.])MCM\.` -> `Crest.MCM.` in .cs/.csproj/.sln/.xml files (namespaces, usings, typerefs)
# - Then surgical fixes happen in step 3 via Cowork tools.
$ErrorActionPreference = 'Continue'

$repoRoot = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen'
cd $repoRoot

$paths = @(
    "$repoRoot\src",
    "$repoRoot\src-ui",
    "$repoRoot\tests"
)

$patterns = '*.cs','*.csproj','*.sln','*.xml','*.props','*.targets'

$files = @()
foreach ($p in $paths) {
    if (Test-Path $p) {
        $files += Get-ChildItem -Recurse -File -Path $p -Include $patterns | Where-Object {
            $_.FullName -notlike '*\bin\*' -and $_.FullName -notlike '*\obj\*'
        }
    }
}
Write-Host "==> Scanning $($files.Count) files..."

$rxBare    = [regex]'(?<![\w.])MCM\.'
$changed = 0
foreach ($f in $files) {
    $content = [System.IO.File]::ReadAllText($f.FullName)
    $orig = $content

    # 1. Bannerlord.MBOptionScreen -> CREST (the historical mod ID)
    $content = $content -replace 'Bannerlord\.MBOptionScreen', 'CREST'

    # 2. Bannerlord.MCM -> Crest.MCM (NuGet package ID and similar)
    $content = $content -replace 'Bannerlord\.MCM', 'Crest.MCM'

    # 3. Bare MCM.* (not preceded by word char or dot) -> Crest.MCM.*
    $content = $rxBare.Replace($content, 'Crest.MCM.')

    if ($content -ne $orig) {
        [System.IO.File]::WriteAllText($f.FullName, $content)
        $changed++
    }
}
Write-Host "    rewrote $changed of $($files.Count)"

Write-Host "`n==> Verification:"
# Should be ZERO remaining hits for these patterns
$remBan = $files | ForEach-Object { Select-String -Path $_.FullName -Pattern 'Bannerlord\.MCM|Bannerlord\.MBOptionScreen' -ErrorAction SilentlyContinue } | Measure-Object
Write-Host "    Bannerlord.MCM/Bannerlord.MBOptionScreen remaining: $($remBan.Count)"

$remBare = $files | ForEach-Object { Select-String -Path $_.FullName -Pattern '(?<![\w.])MCM\.' -ErrorAction SilentlyContinue } | Where-Object { $_.Line -notmatch '"MCM\.' }
Write-Host "    Bare MCM. remaining (excluding string literals): $(($remBare | Measure-Object).Count)"

# Audit: bare MCM\. inside string literals (these may need CREST instead of Crest.MCM)
Write-Host "`n==> String-literal MCM hits to audit:"
$strHits = $files | ForEach-Object { Select-String -Path $_.FullName -Pattern '"MCM[\.\\]|MCM"' -SimpleMatch:$false -ErrorAction SilentlyContinue }
Write-Host "    $(($strHits | Measure-Object).Count) lines with string-literal MCM"
$strHits | Select-Object -First 12 | ForEach-Object { Write-Host "    $($_.Path | Split-Path -Leaf):$($_.LineNumber)  $($_.Line.Trim())" }

exit 0
