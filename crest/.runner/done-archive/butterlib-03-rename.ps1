# ButterLib rebrand step 1 (retry 2): inline git, no splatting.
$ErrorActionPreference = 'Continue'

function CheckExit($what) {
    if ($LASTEXITCODE -ne 0) { throw "$what failed (exit $LASTEXITCODE)" }
}

cd C:\dev\bannerlord\Bannerlord.ButterLib

Write-Host "==> Branch setup"
git checkout master 2>&1 | ForEach-Object { Write-Host "    $_" }
CheckExit "git checkout master"

$existing = git branch --list crest
if ($existing -match 'crest') {
    Write-Host "    crest branch already exists; resetting to master"
    git checkout crest 2>&1 | ForEach-Object { Write-Host "    $_" }
    CheckExit "git checkout crest"
    git reset --hard master 2>&1 | ForEach-Object { Write-Host "    $_" }
    CheckExit "git reset"
} else {
    git checkout -b crest 2>&1 | ForEach-Object { Write-Host "    $_" }
    CheckExit "git checkout -b crest"
}
Write-Host "On branch: $(git rev-parse --abbrev-ref HEAD)"

cd src
Write-Host "`n==> Renaming solution"
if (Test-Path Bannerlord.ButterLib.sln) {
    git mv Bannerlord.ButterLib.sln Crest.ButterLib.sln 2>&1 | ForEach-Object { Write-Host "    $_" }
    CheckExit "git mv sln"
}

Write-Host "`n==> Renaming main library project"
if (Test-Path Bannerlord.ButterLib) {
    git mv Bannerlord.ButterLib Crest.ButterLib 2>&1 | ForEach-Object { Write-Host "    $_" }
    CheckExit "git mv main folder"
    git mv Crest.ButterLib\Bannerlord.ButterLib.csproj Crest.ButterLib\Crest.ButterLib.csproj 2>&1 | ForEach-Object { Write-Host "    $_" }
    CheckExit "git mv main csproj"
}

Write-Host "`n==> Renaming Implementation project"
if (Test-Path Bannerlord.ButterLib.Implementation) {
    git mv Bannerlord.ButterLib.Implementation Crest.ButterLib.Implementation 2>&1 | ForEach-Object { Write-Host "    $_" }
    CheckExit "git mv impl folder"
    git mv Crest.ButterLib.Implementation\Bannerlord.ButterLib.Implementation.csproj Crest.ButterLib.Implementation\Crest.ButterLib.Implementation.csproj 2>&1 | ForEach-Object { Write-Host "    $_" }
    CheckExit "git mv impl csproj"
}

cd ..\tests
Write-Host "`n==> Renaming test projects"
$testDirs = Get-ChildItem -Directory -Filter 'Bannerlord.ButterLib*' -ErrorAction SilentlyContinue
foreach ($d in $testDirs) {
    $newName = $d.Name -replace '^Bannerlord\.ButterLib','Crest.ButterLib'
    Write-Host "  $($d.Name) -> $newName"
    git mv $d.Name $newName 2>&1 | ForEach-Object { Write-Host "    $_" }
    CheckExit "git mv test $($d.Name)"
    $oldCs = "$newName\$($d.Name).csproj"
    $newCs = "$newName\$newName.csproj"
    if (Test-Path $oldCs) {
        git mv $oldCs $newCs 2>&1 | ForEach-Object { Write-Host "    $_" }
        CheckExit "git mv test csproj"
    }
}

cd ..
Write-Host "`n==> Final src/ and tests/ layout:"
Get-ChildItem src -Directory | ForEach-Object { Write-Host "  src\$($_.Name)" }
Get-ChildItem tests -Directory -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  tests\$($_.Name)" }

Write-Host "`n==> Renames staged in git (first 20):"
git status --short | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }

Write-Host "`n==> ButterLib renames complete." -ForegroundColor Green
exit 0
