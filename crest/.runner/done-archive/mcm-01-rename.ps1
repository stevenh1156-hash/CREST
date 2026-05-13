# MCM rebrand step 1: branch + git mv all projects.
$ErrorActionPreference = 'Continue'

function CheckExit($what) {
    if ($LASTEXITCODE -ne 0) { throw "$what failed (exit $LASTEXITCODE)" }
}

cd C:\dev\bannerlord\Bannerlord.MBOptionScreen

Write-Host "==> Branch setup"
git checkout master 2>&1 | ForEach-Object { Write-Host "    $_" }
CheckExit "git checkout master"

$existing = git branch --list crest
if ($existing -match 'crest') {
    Write-Host "    crest branch exists, resetting to master"
    git checkout crest 2>&1 | ForEach-Object { Write-Host "    $_" }
    git reset --hard master 2>&1 | ForEach-Object { Write-Host "    $_" }
} else {
    git checkout -b crest 2>&1 | ForEach-Object { Write-Host "    $_" }
    CheckExit "git checkout -b crest"
}
Write-Host "On branch: $(git rev-parse --abbrev-ref HEAD)"

# Solution rename
Write-Host "`n==> Renaming solution"
cd src
git mv "Mod Configuration Menu.sln" "Crest.MCM.sln" 2>&1 | ForEach-Object { Write-Host "    $_" }
CheckExit "git mv sln"

# src/ project renames
Write-Host "`n==> Renaming src/ projects"
$srcProjects = @(
    @{ Old='MCM';                 New='Crest.MCM' },
    @{ Old='MCM.Abstractions';    New='Crest.MCM.Abstractions' },
    @{ Old='MCM.Bannerlord';      New='Crest.MCM.Bannerlord' },
    @{ Old='MCM.Common';          New='Crest.MCM.Common' },
    @{ Old='MCM.Implementation';  New='Crest.MCM.Implementation' },
    @{ Old='MCM.Source';          New='Crest.MCM.Source' }
)
foreach ($p in $srcProjects) {
    if (Test-Path $p.Old) {
        Write-Host "  src/$($p.Old) -> src/$($p.New)"
        git mv $p.Old $p.New 2>&1 | ForEach-Object { Write-Host "    $_" }
        CheckExit "git mv $($p.Old)"
        $oldCs = "$($p.New)\$($p.Old).csproj"
        $newCs = "$($p.New)\$($p.New).csproj"
        if (Test-Path $oldCs) {
            git mv $oldCs $newCs 2>&1 | ForEach-Object { Write-Host "    $_" }
            CheckExit "git mv csproj"
        }
    }
}

# src-ui/ project renames
cd ..\src-ui
Write-Host "`n==> Renaming src-ui/ projects"
$uiProjects = @(
    @{ Old='MCM.UI';                 New='Crest.MCM.UI' },
    @{ Old='MCM.UI.Adapter.MCMv5';   New='Crest.MCM.UI.Adapter.MCMv5' }
)
foreach ($p in $uiProjects) {
    if (Test-Path $p.Old) {
        Write-Host "  src-ui/$($p.Old) -> src-ui/$($p.New)"
        git mv $p.Old $p.New 2>&1 | ForEach-Object { Write-Host "    $_" }
        CheckExit "git mv $($p.Old)"
        $oldCs = "$($p.New)\$($p.Old).csproj"
        $newCs = "$($p.New)\$($p.New).csproj"
        if (Test-Path $oldCs) {
            git mv $oldCs $newCs 2>&1 | ForEach-Object { Write-Host "    $_" }
            CheckExit "git mv csproj"
        }
    }
}

# tests/ project renames (drop the v5 suffix on MCMv5.Tests)
cd ..\tests
Write-Host "`n==> Renaming tests/ projects"
if (Test-Path 'MCMv5.Tests') {
    git mv MCMv5.Tests Crest.MCM.Tests 2>&1 | ForEach-Object { Write-Host "    $_" }
    git mv "Crest.MCM.Tests\MCMv5.Tests.csproj" "Crest.MCM.Tests\Crest.MCM.Tests.csproj" 2>&1 | ForEach-Object { Write-Host "    $_" }
}
if (Test-Path 'MCM.UnitTests') {
    git mv MCM.UnitTests Crest.MCM.UnitTests 2>&1 | ForEach-Object { Write-Host "    $_" }
    git mv "Crest.MCM.UnitTests\MCM.UnitTests.csproj" "Crest.MCM.UnitTests\Crest.MCM.UnitTests.csproj" 2>&1 | ForEach-Object { Write-Host "    $_" }
}

cd ..
Write-Host "`n==> Final layout:"
Get-ChildItem src -Directory | ForEach-Object { Write-Host "  src\$($_.Name)" }
Get-ChildItem src-ui -Directory | ForEach-Object { Write-Host "  src-ui\$($_.Name)" }
Get-ChildItem tests -Directory | ForEach-Object { Write-Host "  tests\$($_.Name)" }
Write-Host "`n==> Sln rename:"
Get-ChildItem src\*.sln | ForEach-Object { Write-Host "  $($_.Name)" }

Write-Host "`n==> Renames staged (count):"
$staged = (git status --short | Measure-Object).Count
Write-Host "    $staged entries"

Write-Host "`n==> MCM renames complete." -ForegroundColor Green
exit 0
