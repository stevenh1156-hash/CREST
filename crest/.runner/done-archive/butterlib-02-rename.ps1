# ButterLib rebrand step 1 (retry): create crest branch and rename folders/files.
# In PS 5.1, native stderr can trigger NativeCommandError if ErrorActionPreference=Stop.
# Use Continue + explicit $LASTEXITCODE checks for git.
$ErrorActionPreference = 'Continue'

function Invoke-Git {
    param([string[]]$Args)
    Write-Host "git $($Args -join ' ')" -ForegroundColor DarkGray
    & git @Args 2>&1 | ForEach-Object { Write-Host "    $_" }
    if ($LASTEXITCODE -ne 0) { throw "git $($Args -join ' ') failed (exit $LASTEXITCODE)" }
}

cd C:\dev\bannerlord\Bannerlord.ButterLib

Write-Host "==> Branch setup"
Invoke-Git checkout,master
# crest may already exist from a prior partial run
$existing = & git branch --list crest
if ($existing) {
    Write-Host "crest branch already exists; checking out and resetting to master"
    Invoke-Git checkout,crest
    Invoke-Git reset,--hard,master
} else {
    Invoke-Git checkout,-b,crest
}
Write-Host "On branch: $(git rev-parse --abbrev-ref HEAD)"

cd src

Write-Host "`n==> Renaming solution"
if (Test-Path Bannerlord.ButterLib.sln) { Invoke-Git mv,Bannerlord.ButterLib.sln,Crest.ButterLib.sln }

Write-Host "`n==> Renaming main library project"
if (Test-Path Bannerlord.ButterLib) {
    Invoke-Git mv,Bannerlord.ButterLib,Crest.ButterLib
    Invoke-Git mv,Crest.ButterLib\Bannerlord.ButterLib.csproj,Crest.ButterLib\Crest.ButterLib.csproj
}

Write-Host "`n==> Renaming Implementation project"
if (Test-Path Bannerlord.ButterLib.Implementation) {
    Invoke-Git mv,Bannerlord.ButterLib.Implementation,Crest.ButterLib.Implementation
    Invoke-Git mv,Crest.ButterLib.Implementation\Bannerlord.ButterLib.Implementation.csproj,Crest.ButterLib.Implementation\Crest.ButterLib.Implementation.csproj
}

cd ..\tests
Write-Host "`n==> Renaming test projects"
$testDirs = Get-ChildItem -Directory -Filter 'Bannerlord.ButterLib*' -ErrorAction SilentlyContinue
foreach ($d in $testDirs) {
    $newName = $d.Name -replace '^Bannerlord\.ButterLib','Crest.ButterLib'
    Write-Host "  $($d.Name) -> $newName"
    Invoke-Git mv,$d.Name,$newName
    $oldCs = "$newName\$($d.Name).csproj"
    $newCs = "$newName\$newName.csproj"
    if (Test-Path $oldCs) {
        Invoke-Git mv,$oldCs,$newCs
    }
}

cd ..
Write-Host "`n==> Final src/ and tests/ layout (top-level only):"
Get-ChildItem src -Directory | ForEach-Object { Write-Host "  src\$($_.Name)" }
Get-ChildItem tests -Directory -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  tests\$($_.Name)" }

Write-Host "`n==> Renames staged in git:"
& git status --short | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }

exit 0
