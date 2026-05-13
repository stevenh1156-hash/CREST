# MCM step 2b: catch bare `namespace MCM` and `namespace MCM;` declarations
# that weren't matched by the dot-anchored regex.
$ErrorActionPreference = 'Continue'

$repoRoot = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen'

$files = Get-ChildItem -Recurse -File -Path $repoRoot\src,$repoRoot\src-ui,$repoRoot\tests -Include *.cs |
    Where-Object { $_.FullName -notlike '*\bin\*' -and $_.FullName -notlike '*\obj\*' }
Write-Host "==> Scanning $($files.Count) .cs files..."

$changed = 0
foreach ($f in $files) {
    $content = [System.IO.File]::ReadAllText($f.FullName)
    $orig = $content

    # Match `namespace MCM` followed by whitespace+brace OR semicolon (file-scoped) OR end-of-line.
    # The regex: anchor on word boundary, ensure NOT followed by `.` (already-namespaced like MCM.X are handled).
    $content = [regex]::Replace($content, '(?m)^(\s*)namespace MCM(?=[\s\{;\r\n])', '${1}namespace Crest.MCM')

    if ($content -ne $orig) {
        [System.IO.File]::WriteAllText($f.FullName, $content)
        $changed++
    }
}
Write-Host "    rewrote $changed files"

# Verify
Write-Host "`n==> Bare 'namespace MCM' (without Crest. prefix) remaining:"
$rem = $files | ForEach-Object { Select-String -Path $_.FullName -Pattern '^\s*namespace MCM(?![\.\w])' -AllMatches -ErrorAction SilentlyContinue }
Write-Host "    $(($rem | Measure-Object).Count) hits"
$rem | Select-Object -First 5 | ForEach-Object { Write-Host "    $($_.Path | Split-Path -Leaf):$($_.LineNumber)  $($_.Line.Trim())" }

# Final namespace audit: count distinct namespace prefixes
Write-Host "`n==> Distinct namespace declarations now:"
$nss = $files | ForEach-Object { Select-String -Path $_.FullName -Pattern '^\s*namespace (\S+)' -ErrorAction SilentlyContinue } |
    ForEach-Object { ($_.Matches[0].Groups[1].Value -replace '[;{].*$','').Trim() } |
    Group-Object | Sort-Object Count -Descending | Select-Object -First 20
$nss | ForEach-Object { Write-Host ("    {0,5} {1}" -f $_.Count, $_.Name) }

exit 0
