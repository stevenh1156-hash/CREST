# ButterLib step 2: bulk find/replace `Bannerlord.ButterLib` -> `Crest.ButterLib`
# in all .cs, .csproj, .sln, .xml files under the renamed tree.
$ErrorActionPreference = 'Continue'

$repoRoot = 'C:\dev\bannerlord\Bannerlord.ButterLib'
cd $repoRoot

$patterns = '*.cs','*.csproj','*.sln','*.xml','*.props','*.targets'
$paths = @(
    "$repoRoot\src\Crest.ButterLib",
    "$repoRoot\src\Crest.ButterLib.Implementation",
    "$repoRoot\src\Crest.ButterLib.sln",
    "$repoRoot\tests\Crest.ButterLib.HotKeys.Test",
    "$repoRoot\tests\Crest.ButterLib.Tests",
    "$repoRoot\tests\Crest.ButterLib.Implementation.Tests",
    "$repoRoot\tests\Crest.ButterLib.ObjectSystem.Test"
)

$files = @()
foreach ($p in $paths) {
    if (Test-Path $p -PathType Container) {
        $files += Get-ChildItem -Recurse -File -Path $p -Include $patterns
    } elseif (Test-Path $p -PathType Leaf) {
        $files += Get-Item $p
    }
}

Write-Host "==> Scanning $($files.Count) files..."

$changed = 0
foreach ($f in $files) {
    $content = [System.IO.File]::ReadAllText($f.FullName)
    if ($content -match 'Bannerlord\.ButterLib') {
        $newContent = $content -replace 'Bannerlord\.ButterLib', 'Crest.ButterLib'
        [System.IO.File]::WriteAllText($f.FullName, $newContent)
        $changed++
    }
}
Write-Host "    rewrote $changed of $($files.Count)"

Write-Host "`n==> Verifying no Bannerlord.ButterLib remains in source/tests:"
$remaining = $files | ForEach-Object {
    Select-String -Path $_.FullName -Pattern 'Bannerlord\.ButterLib' -SimpleMatch -ErrorAction SilentlyContinue
} | Where-Object { $_ -ne $null }
Write-Host "    remaining hits: $($remaining.Count)"
$remaining | Select-Object -First 10 | ForEach-Object {
    Write-Host "    $($_.Path):$($_.LineNumber)  $($_.Line.Trim())"
}

exit 0
