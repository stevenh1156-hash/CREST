# Revert namespace rebrand attempt #3.
# Uses plain string.Replace() (no regex) and verbose per-file logging to surface
# any silent write failures.

$ErrorActionPreference = 'Continue'

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
        # MCM upstream uses bare `MCM` (not Bannerlord.MCM). Two-step revert:
        #   Crest.MCM. -> MCM.   (with trailing dot for namespace contexts)
        #   Crest.MCM  -> MCM    (anywhere else, e.g. using Crest.MCM;)
        # Order matters: do the trailing-dot one first so we don't mangle.
        Replacements = @(
            @('Crest.MCM.', 'MCM.'),
            @('Crest.MCM',  'MCM')
        )
    }
)

foreach ($fork in $forks) {
    Write-Host ""
    Write-Host "==== $($fork.Name) ====" -ForegroundColor Cyan

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
    $writeFailures = 0
    foreach ($f in $files) {
        try {
            $content = [System.IO.File]::ReadAllText($f.FullName)
        } catch {
            Write-Host ("  ! READ failed for {0}: {1}" -f $f.FullName, $_.Exception.Message) -ForegroundColor Red
            continue
        }

        $orig = $content
        $fileReplacements = 0
        foreach ($pair in $fork.Replacements) {
            # Count manually before string.Replace
            $count = ([regex]::Matches($content, [regex]::Escape($pair[0]))).Count
            if ($count -gt 0) {
                $fileReplacements += $count
                $content = $content.Replace($pair[0], $pair[1])
            }
        }
        if ($fileReplacements -gt 0) {
            $totalReplacements += $fileReplacements
            try {
                # Write with UTF-8 (no BOM) - matches Roslyn's expected encoding
                [System.IO.File]::WriteAllText($f.FullName, $content, [System.Text.UTF8Encoding]::new($false))
                $changedFiles++

                # Verify the write actually persisted
                $check = [System.IO.File]::ReadAllText($f.FullName)
                if ($check -eq $orig) {
                    Write-Host ("  ! VERIFY-FAIL: {0} content unchanged after write ({1} replacements expected)" -f $f.Name, $fileReplacements) -ForegroundColor Red
                    $writeFailures++
                }
            } catch {
                Write-Host ("  ! WRITE failed for {0}: {1}" -f $f.FullName, $_.Exception.Message) -ForegroundColor Red
                $writeFailures++
            }
        }
    }
    Write-Host ("  {0} files rewritten, {1} replacements, {2} write failures" -f $changedFiles, $totalReplacements, $writeFailures)

    # Final verify
    $crestPattern = "Crest\.$($fork.Name)"
    if ($fork.Name -eq 'MCM') { $crestPattern = 'Crest\.MCM' }
    $residual = 0
    $sampleFiles = @()
    foreach ($f in $files) {
        $content = [System.IO.File]::ReadAllText($f.FullName)
        if ($content -match $crestPattern) {
            $residual++
            if ($sampleFiles.Count -lt 3) { $sampleFiles += $f.FullName }
        }
    }
    if ($residual -gt 0) {
        Write-Host ("  residual: $residual files still contain $crestPattern") -ForegroundColor Yellow
        $sampleFiles | ForEach-Object { Write-Host "    e.g. $_" -ForegroundColor DarkYellow }
    } else {
        Write-Host "  CLEAN" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "==== Done ====" -ForegroundColor Green
