# Revert namespace rebrand attempt #2 - explicit changed-flag instead of relying
# on string -ne comparison (which silently failed in revert-01).

$ErrorActionPreference = 'Continue'

$forks = @(
    @{
        Name = 'Harmony'
        RepoRoot = 'C:\dev\bannerlord\Bannerlord.Harmony'
        Replacements = @(
            @('Crest.Harmony', 'Bannerlord.Harmony')
        )
        VerifyPattern = 'Crest\.Harmony'
    },
    @{
        Name = 'ButterLib'
        RepoRoot = 'C:\dev\bannerlord\Bannerlord.ButterLib'
        Replacements = @(
            @('Crest.ButterLib', 'Bannerlord.ButterLib')
        )
        VerifyPattern = 'Crest\.ButterLib'
    },
    @{
        Name = 'UIExtenderEx'
        RepoRoot = 'C:\dev\bannerlord\Bannerlord.UIExtenderEx'
        Replacements = @(
            @('Crest.UIExtenderEx', 'Bannerlord.UIExtenderEx')
        )
        VerifyPattern = 'Crest\.UIExtenderEx'
    },
    @{
        Name = 'MCM'
        RepoRoot = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen'
        # MCM upstream uses bare `MCM` namespace (not Bannerlord.MCM).
        # Match Crest.MCM not followed by alphanum/underscore so we don't catch e.g. Crest.MCMv5.
        Replacements = @(
            @('Crest\.MCM(?![A-Za-z0-9_])', 'MCM')
        )
        VerifyPattern = 'Crest\.MCM'
    }
)

foreach ($fork in $forks) {
    Write-Host ""
    Write-Host "==== $($fork.Name) ====" -ForegroundColor Cyan
    if (-not (Test-Path $fork.RepoRoot)) {
        Write-Host "  SKIP - repo not found" -ForegroundColor Yellow
        continue
    }

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
        $hadChanges = $false
        foreach ($pair in $fork.Replacements) {
            $rx = [regex]::new($pair[0])
            $mc = $rx.Matches($content)
            if ($mc.Count -gt 0) {
                $totalReplacements += $mc.Count
                $content = $rx.Replace($content, $pair[1])
                $hadChanges = $true
            }
        }
        if ($hadChanges) {
            try {
                [System.IO.File]::WriteAllText($f.FullName, $content)
                $changedFiles++
            } catch {
                Write-Host ("  ! write failed for {0}: {1}" -f $f.FullName, $_.Exception.Message) -ForegroundColor Red
            }
        }
    }
    Write-Host "  rewrote $changedFiles files ($totalReplacements replacements)"

    # Verify
    $residual = 0
    foreach ($f in $files) {
        $hits = Select-String -Path $f.FullName -Pattern $fork.VerifyPattern -ErrorAction SilentlyContinue
        $residual += ($hits | Measure-Object).Count
    }
    if ($residual -gt 0) {
        Write-Host "  residual hits: $residual" -ForegroundColor Yellow
        # Show a few samples
        $samples = @()
        foreach ($f in $files) {
            $samples += Select-String -Path $f.FullName -Pattern $fork.VerifyPattern -ErrorAction SilentlyContinue
            if ($samples.Count -ge 6) { break }
        }
        $samples | Select-Object -First 6 | ForEach-Object {
            Write-Host ("    {0}:{1}  {2}" -f ($_.Path | Split-Path -Leaf), $_.LineNumber, $_.Line.Trim())
        }
    } else {
        Write-Host "  CLEAN - no $($fork.VerifyPattern) references in .cs" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "==== Done ====" -ForegroundColor Green
