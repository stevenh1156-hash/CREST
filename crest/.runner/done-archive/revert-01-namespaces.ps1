# Phase H prerequisite: revert the Phase B namespace rebrand in C# source ONLY.
# Build-system metadata (csproj, sln, props, targets) keeps CREST branding
# (AssemblyName=Crest.X, package IDs, etc.) so artifacts still ship as
# Crest.X.dll. Only the `namespace`, `using`, and qualified type references
# in .cs files revert to Bannerlord.X.* / MCM.* upstream names.
#
# Once this runs:
#   - Crest.X.dll's public types are FQN'd `Bannerlord.X.Foo` (or `MCM.Foo` for MCM)
#   - Phase H shim `Bannerlord.X.dll` forwards `Bannerlord.X.Foo` -> Crest.X.dll!Bannerlord.X.Foo
#   - Standard TypeForwardedTo pattern works (source FQN == destination FQN)
#   - Existing community mods compiled against upstream BUTR libs work unchanged

$ErrorActionPreference = 'Continue'

# (fork repo, namespace-rename pairs to apply in REVERSE order)
$forks = @(
    @{
        Name = 'Harmony'
        RepoRoot = 'C:\dev\bannerlord\Bannerlord.Harmony'
        Replacements = @(
            @('Crest.Harmony', 'Bannerlord.Harmony')
        )
    },
    @{
        Name = 'ButterLib'
        RepoRoot = 'C:\dev\bannerlord\Bannerlord.ButterLib'
        Replacements = @(
            @('Crest.ButterLib', 'Bannerlord.ButterLib')
        )
    },
    @{
        Name = 'UIExtenderEx'
        RepoRoot = 'C:\dev\bannerlord\Bannerlord.UIExtenderEx'
        Replacements = @(
            @('Crest.UIExtenderEx', 'Bannerlord.UIExtenderEx')
        )
    },
    @{
        Name = 'MCM'
        RepoRoot = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen'
        # MCM is special: upstream uses bare `MCM` namespace (not `Bannerlord.MCM`)
        # Use lookahead to ensure we don't catch e.g. "Crest.MCMv5"
        Replacements = @(
            @('Crest\.MCM(?![A-Za-z0-9_])', 'MCM')
        )
    }
)

foreach ($fork in $forks) {
    Write-Host ""
    Write-Host "==== $($fork.Name) ====" -ForegroundColor Cyan
    if (-not (Test-Path $fork.RepoRoot)) {
        Write-Host "  SKIP - repo not found" -ForegroundColor Yellow
        continue
    }

    # Collect all .cs files under src/, src-ui/, tests/, excluding bin/ and obj/
    $files = @()
    foreach ($subdir in @('src','src-ui','tests')) {
        $path = Join-Path $fork.RepoRoot $subdir
        if (Test-Path $path) {
            $files += Get-ChildItem -Recurse -File -Path $path -Include '*.cs' -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notlike '*\bin\*' -and $_.FullName -notlike '*\obj\*' }
        }
    }
    Write-Host "  scanning $($files.Count) .cs files"

    $changedFiles = 0
    $totalReplacements = 0
    foreach ($f in $files) {
        $content = [System.IO.File]::ReadAllText($f.FullName)
        $orig = $content
        foreach ($pair in $fork.Replacements) {
            $matches = [regex]::Matches($content, $pair[0])
            $totalReplacements += $matches.Count
            $content = [regex]::Replace($content, $pair[0], $pair[1])
        }
        if ($content -ne $orig) {
            [System.IO.File]::WriteAllText($f.FullName, $content)
            $changedFiles++
        }
    }
    Write-Host "  rewrote $changedFiles files ($totalReplacements replacements)"

    # Verify - count residual Crest.<X>. occurrences
    $crestPrefix = "Crest.$($fork.Name)"
    if ($fork.Name -eq 'Harmony') { $crestPrefix = 'Crest.Harmony' }
    if ($fork.Name -eq 'ButterLib') { $crestPrefix = 'Crest.ButterLib' }
    if ($fork.Name -eq 'UIExtenderEx') { $crestPrefix = 'Crest.UIExtenderEx' }
    if ($fork.Name -eq 'MCM') { $crestPrefix = 'Crest.MCM' }

    $residual = $files | ForEach-Object {
        Select-String -Path $_.FullName -Pattern $crestPrefix -ErrorAction SilentlyContinue
    } | Where-Object { $_ -ne $null }
    $residCount = ($residual | Measure-Object).Count
    if ($residCount -gt 0) {
        Write-Host "  residual hits ($residCount):" -ForegroundColor Yellow
        $residual | Select-Object -First 5 | ForEach-Object {
            Write-Host ("    {0}:{1}  {2}" -f ($_.Path | Split-Path -Leaf), $_.LineNumber, $_.Line.Trim())
        }
    } else {
        Write-Host "  CLEAN - no $crestPrefix references remain in .cs" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "==== Revert complete ====" -ForegroundColor Green
Write-Host "Next: Build-AllCrestRepos to verify everything still compiles, then re-run shim generator."
