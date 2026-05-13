$ErrorActionPreference = 'Continue'

# Step 1: hard reset src/, src-ui/, tests/ in each fork to HEAD
$repos = @(
    'C:\dev\bannerlord\Bannerlord.Harmony',
    'C:\dev\bannerlord\Bannerlord.ButterLib',
    'C:\dev\bannerlord\Bannerlord.UIExtenderEx',
    'C:\dev\bannerlord\Bannerlord.MBOptionScreen'
)

Write-Host "==> Step 1: hard reset uncommitted changes in src/ src-ui/ tests/" -ForegroundColor Cyan
foreach ($r in $repos) {
    Push-Location $r
    try {
        Write-Host "---- $r ----" -ForegroundColor DarkCyan
        $before = (git status --short | Where-Object { $_ } | Measure-Object).Count
        foreach ($d in @('src','src-ui','tests')) {
            if (Test-Path (Join-Path $r $d)) {
                git checkout HEAD -- $d 2>&1 | Out-Null
            }
        }
        $after = (git status --short | Where-Object { $_ } | Measure-Object).Count
        Write-Host "  uncommitted before: $before  after: $after"
    } finally { Pop-Location }
}

# Step 2: Clean namespace revert using plain-string Replace on the clean state
Write-Host ""
Write-Host "==> Step 2: clean namespace revert (Crest.X.* -> Bannerlord.X.* / MCM.*)" -ForegroundColor Cyan

$forks = @(
    @{ Name='Harmony';      RepoRoot='C:\dev\bannerlord\Bannerlord.Harmony';
       Replacements = @( @('Crest.Harmony', 'Bannerlord.Harmony') ) },
    @{ Name='ButterLib';    RepoRoot='C:\dev\bannerlord\Bannerlord.ButterLib';
       Replacements = @( @('Crest.ButterLib', 'Bannerlord.ButterLib') ) },
    @{ Name='UIExtenderEx'; RepoRoot='C:\dev\bannerlord\Bannerlord.UIExtenderEx';
       Replacements = @( @('Crest.UIExtenderEx', 'Bannerlord.UIExtenderEx') ) },
    @{ Name='MCM';          RepoRoot='C:\dev\bannerlord\Bannerlord.MBOptionScreen';
       Replacements = @( @('Crest.MCM.', 'MCM.'), @('Crest.MCM', 'MCM') ) }
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
    foreach ($f in $files) {
        $content = [System.IO.File]::ReadAllText($f.FullName)
        $orig = $content
        $fileChanges = 0
        foreach ($pair in $fork.Replacements) {
            # Plain string Replace - count first via regex.Escape for accurate counting
            $count = ([regex]::Matches($content, [regex]::Escape($pair[0]))).Count
            if ($count -gt 0) {
                $fileChanges += $count
                $content = $content.Replace($pair[0], $pair[1])
            }
        }
        if ($fileChanges -gt 0) {
            $totalReplacements += $fileChanges
            try {
                [System.IO.File]::WriteAllText($f.FullName, $content, [System.Text.UTF8Encoding]::new($false))
                # Verify the write
                $check = [System.IO.File]::ReadAllText($f.FullName)
                if ($check -ne $orig) { $changed++ }
                else { Write-Host ("  ! verify failed: $($f.Name) unchanged after write") -ForegroundColor Red }
            } catch {
                Write-Host ("  ! write failed for $($f.FullName): $($_.Exception.Message)") -ForegroundColor Red
            }
        }
    }
    Write-Host "  rewrote $changed files / $totalReplacements replacements"

    # Verify - residual count
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

# Step 3: spot-check a couple of files visually
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
        $first10 = (Get-Content $s -TotalCount 10) -join "`n"
        $nsLine = $first10 -split "`n" | Where-Object { $_ -match '^namespace\s' } | Select-Object -First 1
        Write-Host ("  {0}" -f (Split-Path $s -Leaf))
        Write-Host ("    {0}" -f $nsLine)
    }
}

Write-Host ""
Write-Host "==== Reset + revert complete ====" -ForegroundColor Green
Write-Host "Next: re-apply csproj edits + diagnostic instrumentation + ValidateLoadOrder neutering"
