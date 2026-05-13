# Bug fix 1: MCM.UI cross-fork references.
# - Replace `Bannerlord.UIExtenderEx` -> `Crest.UIExtenderEx` and `Bannerlord.ButterLib` -> `Crest.ButterLib` in 8 .cs files
# - Verify no remaining hits
$ErrorActionPreference = 'Continue'

$mcmUiDir = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI'
cd C:\dev\bannerlord\Bannerlord.MBOptionScreen

Write-Host "==> Bulk replace in MCM.UI source..." -ForegroundColor Cyan
$files = Get-ChildItem -Recurse -File -Path $mcmUiDir -Include *.cs |
    Where-Object { $_.FullName -notlike '*\bin\*' -and $_.FullName -notlike '*\obj\*' }

$changed = 0
foreach ($f in $files) {
    $content = [System.IO.File]::ReadAllText($f.FullName)
    $orig = $content
    $content = $content -replace 'Bannerlord\.UIExtenderEx', 'Crest.UIExtenderEx'
    $content = $content -replace 'Bannerlord\.ButterLib', 'Crest.ButterLib'
    if ($content -ne $orig) {
        [System.IO.File]::WriteAllText($f.FullName, $content)
        $changed++
        Write-Host "    updated: $($f.Name)"
    }
}
Write-Host "==> $changed of $($files.Count) files updated"

Write-Host "`n==> Audit remaining cross-fork BUTR refs in MCM:"
$rem = Get-ChildItem -Recurse -File -Path 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src','C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui' -Include *.cs |
    Where-Object { $_.FullName -notlike '*\bin\*' -and $_.FullName -notlike '*\obj\*' } |
    ForEach-Object { Select-String -Path $_.FullName -Pattern 'using Bannerlord\.(UIExtenderEx|ButterLib|Harmony)' -ErrorAction SilentlyContinue }
$remCount = ($rem | Measure-Object).Count
Write-Host "    remaining hits: $remCount"
$rem | Select-Object -First 10 | ForEach-Object { Write-Host "    $($_.Path | Split-Path -Leaf):$($_.LineNumber)  $($_.Line.Trim())" }

exit 0
