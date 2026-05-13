# ButterLib step 4: fix relative-namespace resolution.
# In upstream, code like `BUTR.Shared.Helpers.X` resolved relative to
# `namespace Bannerlord.ButterLib.*` -> `Bannerlord.BUTR.Shared.Helpers.X`.
# After our namespace rename to Crest.ButterLib.*, those inline refs no longer resolve.
# Fully qualify them by adding `Bannerlord.` prefix where missing.
$ErrorActionPreference = 'Continue'

$repoRoot = 'C:\dev\bannerlord\Bannerlord.ButterLib'
cd $repoRoot

# Find every .cs file under our renamed src
$files = Get-ChildItem -Recurse -File -Path $repoRoot\src\Crest.ButterLib,$repoRoot\src\Crest.ButterLib.Implementation -Include *.cs

$changed = 0
foreach ($f in $files) {
    $content = [System.IO.File]::ReadAllText($f.FullName)
    $orig = $content

    # Negative lookbehind for "Bannerlord." or "Crest." or word char (so "MyBUTR.Shared" doesn't match).
    # We anchor on word boundary then "BUTR.Shared." not preceded by namespace prefix.
    $content = [regex]::Replace($content, '(?<![\w\.])BUTR\.Shared\.', 'Bannerlord.BUTR.Shared.')

    if ($content -ne $orig) {
        [System.IO.File]::WriteAllText($f.FullName, $content)
        $changed++
    }
}
Write-Host "==> Files updated: $changed of $($files.Count)"

# Audit: any more bare 'BUTR.' references in .cs files (excluding fully-qualified Bannerlord.BUTR or BUTR.CrashReport, BUTR.DependencyInjection, BUTR.MessageBoxPInvoke - these are legitimate top-level BUTR namespaces from other packages)
Write-Host ""
Write-Host "==> Audit: bare BUTR. references that may still need qualifying"
$hits = $files | ForEach-Object {
    Select-String -Path $_.FullName -Pattern '(?<![\w\.])BUTR\.' -ErrorAction SilentlyContinue
} | Where-Object { $_.Line -notmatch 'BUTR\.(CrashReport|DependencyInjection|MessageBoxPInvoke|Harmony)' -and $_.Line -notmatch '^//|^\s*\*' }
Write-Host "    $($hits.Count) lines"
$hits | Select-Object -First 15 | ForEach-Object { Write-Host "    $($_.Path | Split-Path -Leaf):$($_.LineNumber)  $($_.Line.Trim())" }

exit 0
