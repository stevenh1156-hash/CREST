$ErrorActionPreference = 'Continue'

# Step 1: hard reset .cs file corruption (keep csproj/sln/etc as-is)
$repos = @(
    'C:\dev\bannerlord\Bannerlord.Harmony',
    'C:\dev\bannerlord\Bannerlord.ButterLib',
    'C:\dev\bannerlord\Bannerlord.UIExtenderEx',
    'C:\dev\bannerlord\Bannerlord.MBOptionScreen'
)
Write-Host "==> Step 1: hard reset .cs files in src/, src-ui/, tests/" -ForegroundColor Cyan
foreach ($r in $repos) {
    Push-Location $r
    try {
        Write-Host "---- $r ----" -ForegroundColor DarkCyan
        # Only reset .cs files - leave csproj/sln/xml alone (those are intentional changes)
        # Use git pathspec to target .cs only
        foreach ($d in @('src','src-ui','tests')) {
            $path = Join-Path $r $d
            if (Test-Path $path) {
                # Use git ls-files + grep to find tracked .cs files, then checkout each
                $csFiles = git ls-files "$d/*.cs" 2>$null
                if ($csFiles) {
                    $csFiles | ForEach-Object { git checkout HEAD -- $_ 2>&1 | Out-Null }
                }
            }
        }
        $after = (git status --short | Where-Object { $_ } | Measure-Object).Count
        Write-Host "  uncommitted after .cs reset: $after"
    } finally { Pop-Location }
}

# Step 2: namespace revert with FIXED array handling.
# Use parallel From[]/To[] arrays instead of nested arrays to avoid PS flattening.
Write-Host ""
Write-Host "==> Step 2: namespace revert with parallel From[]/To[] (no nested array)" -ForegroundColor Cyan

$forks = @(
    @{
        Name='Harmony'
        RepoRoot='C:\dev\bannerlord\Bannerlord.Harmony'
        From = @('Crest.Harmony')
        To   = @('Bannerlord.Harmony')
    },
    @{
        Name='ButterLib'
        RepoRoot='C:\dev\bannerlord\Bannerlord.ButterLib'
        From = @('Crest.ButterLib')
        To   = @('Bannerlord.ButterLib')
    },
    @{
        Name='UIExtenderEx'
        RepoRoot='C:\dev\bannerlord\Bannerlord.UIExtenderEx'
        From = @('Crest.UIExtenderEx')
        To   = @('Bannerlord.UIExtenderEx')
    },
    @{
        Name='MCM'
        RepoRoot='C:\dev\bannerlord\Bannerlord.MBOptionScreen'
        # MCM upstream uses bare `MCM` namespace. Two-step: longer-prefix first.
        From = @('Crest.MCM.', 'Crest.MCM')
        To   = @('MCM.',       'MCM')
    }
)

foreach ($fork in $forks) {
    Write-Host ""
    Write-Host "---- $($fork.Name) ----" -ForegroundColor Cyan
    $files = @()
    foreach ($subdir in @('src','src-ui','tests')) {
        $path = Join-Path $fork.RepoRoot $subdir
        if (Test-Path $path) {
            $files += Get-ChildItem -Recurse -File -Path $path -Include '*.cs' -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notlike '*\bin\*' -and $_.FullName -notlike '*\obj\*' }
        }
    }
    Write-Host "  scanning $($files.Count) .cs files"

    $changed = 0
    $totalReplacements = 0
    $writeFails = 0

    foreach ($f in $files) {
        $content = [System.IO.File]::ReadAllText($f.FullName)
        $orig = $content
        $fileChanges = 0

        # Iterate by INDEX to avoid foreach flattening
        for ($i = 0; $i -lt $fork.From.Count; $i++) {
            $find = $fork.From[$i]
            $replace = $fork.To[$i]
            # Sanity-check: $find and $replace must be the full strings, not first chars
            if ($find.Length -lt 5) {
                Write-Host "  ! BAIL OUT - find=$find replace=$replace (looks wrong)" -ForegroundColor Red
                exit 99
            }
            $count = ([regex]::Matches($content, [regex]::Escape($find))).Count
            if ($count -gt 0) {
                $fileChanges += $count
                $content = $content.Replace($find, $replace)
            }
        }

        if ($fileChanges -gt 0) {
            $totalReplacements += $fileChanges
            try {
                [System.IO.File]::WriteAllText($f.FullName, $content, [System.Text.UTF8Encoding]::new($false))
                $check = [System.IO.File]::ReadAllText($f.FullName)
                if ($check -ne $orig) { $changed++ }
                else { $writeFails++ }
            } catch {
                Write-Host ("  ! write failed for $($f.FullName): $($_.Exception.Message)") -ForegroundColor Red
                $writeFails++
            }
        }
    }
    Write-Host "  rewrote $changed files / $totalReplacements replacements / $writeFails write fails"

    # Verify
    $crestPattern = if ($fork.Name -eq 'MCM') { 'Crest\.MCM' } else { "Crest\.$($fork.Name)" }
    $residualFiles = 0
    foreach ($f in $files) {
        $c = [System.IO.File]::ReadAllText($f.FullName)
        if ($c -match $crestPattern) { $residualFiles++ }
    }
    if ($residualFiles -gt 0) {
        Write-Host "  residual: $residualFiles files still match $crestPattern" -ForegroundColor Yellow
    } else {
        Write-Host "  CLEAN" -ForegroundColor Green
    }
}

# Step 3: spot-check
Write-Host ""
Write-Host "==> Step 3: spot-check namespace declarations" -ForegroundColor Cyan
$samples = @(
    'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\HarmonyRef.cs',
    'C:\dev\bannerlord\Bannerlord.ButterLib\src\Crest.ButterLib\CrashUploader\CrashUploaderResult.cs',
    'C:\dev\bannerlord\Bannerlord.UIExtenderEx\src\Crest.UIExtenderEx\Attributes\BaseUIExtenderAttribute.cs',
    'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src\Crest.MCM\MCMSubModule.cs'
)
foreach ($s in $samples) {
    if (Test-Path $s) {
        $first = (Get-Content $s -TotalCount 30) -join "`n"
        $nsLine = ($first -split "`n") | Where-Object { $_ -match '^\s*namespace\s' } | Select-Object -First 1
        Write-Host ("  {0,-50} {1}" -f (Split-Path $s -Leaf), $nsLine.Trim())
    }
}

Write-Host ""
Write-Host "==== Done ====" -ForegroundColor Green
