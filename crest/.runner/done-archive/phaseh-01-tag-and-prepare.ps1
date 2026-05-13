$ErrorActionPreference = 'Continue'

# Step 1: tag v1.0.0 on every fork repo so we can roll back instantly
$repos = @(
    'C:\dev\bannerlord\Bannerlord.Harmony',
    'C:\dev\bannerlord\Bannerlord.ButterLib',
    'C:\dev\bannerlord\Bannerlord.UIExtenderEx',
    'C:\dev\bannerlord\Bannerlord.MBOptionScreen'
)

Write-Host "==> Step 1: tag v1.0.0 on each fork (rollback safety net)" -ForegroundColor Cyan
foreach ($r in $repos) {
    Push-Location $r
    try {
        $existing = git tag -l v1.0.0 2>$null
        if ($existing) {
            Write-Host ("  {0}: tag v1.0.0 already exists" -f (Split-Path $r -Leaf)) -ForegroundColor DarkGray
            continue
        }
        $sha = (git rev-parse --short HEAD 2>$null).Trim()
        git tag -a v1.0.0 -m "CREST v1.0.0 ship checkpoint" 2>&1 | Out-Null
        Write-Host ("  {0}: tagged v1.0.0 at {1}" -f (Split-Path $r -Leaf), $sha) -ForegroundColor Green
    } finally { Pop-Location }
}

# Step 2: hard reset .cs files in src/, src-ui/, tests/ - clears any stale uncommitted changes
# (commits are all in v1.0 now, so this is just paranoia)
Write-Host ""
Write-Host "==> Step 2: clean working trees" -ForegroundColor Cyan
foreach ($r in $repos) {
    Push-Location $r
    try {
        git status --short | Where-Object { $_ } | ForEach-Object { Write-Host ("    UNCOMMITTED in {0}: {1}" -f (Split-Path $r -Leaf), $_.Trim()) -ForegroundColor Yellow }
        # Don't auto-revert - just report. v1.0 commits should mean clean trees.
    } finally { Pop-Location }
}

# Step 3: namespace revert across all 4 forks (using the proven plain-string approach)
Write-Host ""
Write-Host "==> Step 3: namespace revert in .cs files" -ForegroundColor Cyan

$forks = @(
    @{ Name='Harmony';      RepoRoot='C:\dev\bannerlord\Bannerlord.Harmony';
       From=@('Crest.Harmony');         To=@('Bannerlord.Harmony') },
    @{ Name='ButterLib';    RepoRoot='C:\dev\bannerlord\Bannerlord.ButterLib';
       From=@('Crest.ButterLib');       To=@('Bannerlord.ButterLib') },
    @{ Name='UIExtenderEx'; RepoRoot='C:\dev\bannerlord\Bannerlord.UIExtenderEx';
       From=@('Crest.UIExtenderEx');    To=@('Bannerlord.UIExtenderEx') },
    @{ Name='MCM';          RepoRoot='C:\dev\bannerlord\Bannerlord.MBOptionScreen';
       From=@('Crest.MCM.', 'Crest.MCM');  To=@('MCM.', 'MCM') }
)

foreach ($fork in $forks) {
    Write-Host ""
    Write-Host "---- $($fork.Name) ----" -ForegroundColor DarkCyan
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
        for ($i = 0; $i -lt $fork.From.Count; $i++) {
            $find = $fork.From[$i]
            $replace = $fork.To[$i]
            if ($find.Length -lt 5) { Write-Host "  ! BAIL OUT - find too short" -ForegroundColor Red; exit 99 }
            $count = ([regex]::Matches($content, [regex]::Escape($find))).Count
            if ($count -gt 0) {
                $fileChanges += $count
                $content = $content.Replace($find, $replace)
            }
        }
        if ($fileChanges -gt 0) {
            $totalReplacements += $fileChanges
            [System.IO.File]::WriteAllText($f.FullName, $content, [System.Text.UTF8Encoding]::new($false))
            $changed++
        }
    }
    Write-Host "  rewrote $changed files / $totalReplacements replacements"
}

# Step 4: cross-fork using-statement revert in MCM (its source references Crest.ButterLib + Crest.UIExtenderEx + Crest.Harmony)
Write-Host ""
Write-Host "==> Step 4: cross-fork using statements in MCM" -ForegroundColor Cyan
$mcmRoot = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen'
$crossFrom = @('Crest.ButterLib', 'Crest.UIExtenderEx', 'Crest.Harmony')
$crossTo   = @('Bannerlord.ButterLib', 'Bannerlord.UIExtenderEx', 'Bannerlord.Harmony')
$mcmFiles = @()
foreach ($subdir in @('src','src-ui','tests')) {
    $path = Join-Path $mcmRoot $subdir
    if (Test-Path $path) {
        $mcmFiles += Get-ChildItem -Recurse -File -Path $path -Include '*.cs' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notlike '*\bin\*' -and $_.FullName -notlike '*\obj\*' }
    }
}
$crossChanged = 0
$crossReplaced = 0
foreach ($f in $mcmFiles) {
    $content = [System.IO.File]::ReadAllText($f.FullName)
    $orig = $content
    $fileChanges = 0
    for ($i = 0; $i -lt $crossFrom.Count; $i++) {
        $count = ([regex]::Matches($content, [regex]::Escape($crossFrom[$i]))).Count
        if ($count -gt 0) {
            $fileChanges += $count
            $content = $content.Replace($crossFrom[$i], $crossTo[$i])
        }
    }
    if ($fileChanges -gt 0) {
        $crossReplaced += $fileChanges
        [System.IO.File]::WriteAllText($f.FullName, $content, [System.Text.UTF8Encoding]::new($false))
        $crossChanged++
    }
}
Write-Host "  rewrote $crossChanged files / $crossReplaced cross-fork replacements"

# Step 5: also patch Crest.ButterLib and Crest.UIExtenderEx for the CrestConfig reflection lookup
# (they reference 'Crest.Harmony.CrestConfig, Crest.Harmony' which becomes 'Bannerlord.Harmony.CrestConfig, Crest.Harmony')
Write-Host ""
Write-Host "==> Step 5: update CrestConfig reflection lookups in ButterLib + MCM" -ForegroundColor Cyan
$reflectionTargets = @(
    'C:\dev\bannerlord\Bannerlord.ButterLib\src\Crest.ButterLib\ButterLibSubModule.cs',
    'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src\Crest.MCM\MCMSubModule.cs',
    'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src\Crest.MCM.Bannerlord\MCMImplementationSubModule.cs'
)
foreach ($f in $reflectionTargets) {
    if (Test-Path $f) {
        $content = [System.IO.File]::ReadAllText($f)
        # The above namespace revert already converted Crest.X strings literals where they're used as namespaces.
        # The reflection string "Crest.Harmony.CrestConfig, Crest.Harmony" should now be
        # "Bannerlord.Harmony.CrestConfig, Crest.Harmony" - but the namespace pattern only changed prefix part of FQN.
        # Verify by reading the file
        if ($content -match 'Crest\.Harmony\.CrestConfig') {
            Write-Host ("    [need fix] {0}: still has Crest.Harmony.CrestConfig" -f (Split-Path $f -Leaf))
            $newContent = $content.Replace('Crest.Harmony.CrestConfig, Crest.Harmony', 'Bannerlord.Harmony.CrestConfig, Crest.Harmony')
            [System.IO.File]::WriteAllText($f, $newContent, [System.Text.UTF8Encoding]::new($false))
        } else {
            Write-Host ("    [ok] {0}: no stale CrestConfig reference" -f (Split-Path $f -Leaf))
        }
    }
}

# Step 6: update RootNamespace + add ExcludeAssets for cross-fork upstream NuGets in csprojs
Write-Host ""
Write-Host "==> Step 6: csproj updates (RootNamespace + transitive NuGet excludes)" -ForegroundColor Cyan
$csprojUpdates = @(
    @{ Path='C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\Crest.Harmony.csproj';
       Find='<RootNamespace>Crest.Harmony</RootNamespace>'; Replace='<RootNamespace>Bannerlord.Harmony</RootNamespace>' },
    @{ Path='C:\dev\bannerlord\Bannerlord.ButterLib\src\Crest.ButterLib\Crest.ButterLib.csproj';
       Find='<RootNamespace>Crest.ButterLib</RootNamespace>'; Replace='<RootNamespace>Bannerlord.ButterLib</RootNamespace>' },
    @{ Path='C:\dev\bannerlord\Bannerlord.ButterLib\src\Crest.ButterLib.Implementation\Crest.ButterLib.Implementation.csproj';
       Find='<RootNamespace>Crest.ButterLib.Implementation</RootNamespace>'; Replace='<RootNamespace>Bannerlord.ButterLib.Implementation</RootNamespace>' },
    @{ Path='C:\dev\bannerlord\Bannerlord.UIExtenderEx\src\Crest.UIExtenderEx\Crest.UIExtenderEx.csproj';
       Find='<RootNamespace>Crest.UIExtenderEx</RootNamespace>'; Replace='<RootNamespace>Bannerlord.UIExtenderEx</RootNamespace>' },
    @{ Path='C:\dev\bannerlord\Bannerlord.MBOptionScreen\src\Crest.MCM\Crest.MCM.csproj';
       Find='<RootNamespace>Crest.MCM</RootNamespace>'; Replace='<RootNamespace>MCM</RootNamespace>' }
)
foreach ($u in $csprojUpdates) {
    if (Test-Path $u.Path) {
        $content = [System.IO.File]::ReadAllText($u.Path)
        if ($content -match [regex]::Escape($u.Find)) {
            $newContent = $content.Replace($u.Find, $u.Replace)
            [System.IO.File]::WriteAllText($u.Path, $newContent, [System.Text.UTF8Encoding]::new($false))
            Write-Host ("    updated RootNamespace in {0}" -f (Split-Path $u.Path -Leaf))
        }
    }
}

# Add ExcludeAssets for upstream BUTR transitive NuGets in MCM.UI csproj
$mcmUi = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI\Crest.MCM.UI.csproj'
if (Test-Path $mcmUi) {
    $content = [System.IO.File]::ReadAllText($mcmUi)
    if ($content -notmatch 'Bannerlord\.ButterLib.*ExcludeAssets="all"') {
        $marker = '<PackageReference Include="BUTR.MessageBoxPInvoke" Version="1.0.0.1" />'
        if ($content.Contains($marker)) {
            $insert = $marker + @"

`r`n
    <!-- Phase H: suppress upstream Bannerlord.ButterLib / Bannerlord.UIExtenderEx that BUTR.DependencyInjection.ButterLib pulls in transitively. After namespace revert our Crest.* DLLs define types under Bannerlord.* namespace which would collide with the upstream NuGets. ExcludeAssets="all" makes the upstream NuGet contribute nothing. -->
    <PackageReference Include="Bannerlord.ButterLib" Version="*" ExcludeAssets="all" PrivateAssets="all" />
    <PackageReference Include="Bannerlord.UIExtenderEx" Version="*" ExcludeAssets="all" PrivateAssets="all" />
"@
            $newContent = $content.Replace($marker, $insert)
            [System.IO.File]::WriteAllText($mcmUi, $newContent, [System.Text.UTF8Encoding]::new($false))
            Write-Host "    added Bannerlord.ButterLib + Bannerlord.UIExtenderEx ExcludeAssets to MCM.UI csproj"
        }
    }
}

Write-Host ""
Write-Host "==== Phase H prep complete ====" -ForegroundColor Green
Write-Host "Next: build all 4 forks, flip-internals, generate shims, deploy."
