# ButterLib rebrand step 1: create crest branch and rename folders/files.
$ErrorActionPreference = 'Stop'

cd C:\dev\bannerlord\Bannerlord.ButterLib

Write-Host "==> Switching to master and creating crest branch..."
git checkout master 2>&1 | Out-Host
git checkout -b crest 2>&1 | Out-Host
Write-Host "Branch: $(git rev-parse --abbrev-ref HEAD)"

# Rename solution
Write-Host "`n==> Renaming solution..."
cd src
git mv Bannerlord.ButterLib.sln Crest.ButterLib.sln

# Rename main library project
Write-Host "==> Renaming main library project..."
git mv Bannerlord.ButterLib Crest.ButterLib
git mv Crest.ButterLib\Bannerlord.ButterLib.csproj Crest.ButterLib\Crest.ButterLib.csproj

# Rename Implementation project
Write-Host "==> Renaming Implementation project..."
git mv Bannerlord.ButterLib.Implementation Crest.ButterLib.Implementation
git mv Crest.ButterLib.Implementation\Bannerlord.ButterLib.Implementation.csproj Crest.ButterLib.Implementation\Crest.ButterLib.Implementation.csproj

# Rename test projects too (for InternalsVisibleTo consistency)
cd ..\tests
Write-Host "`n==> Renaming test projects..."
foreach ($d in (Get-ChildItem -Directory -Filter 'Bannerlord.ButterLib*')) {
    $newName = $d.Name -replace '^Bannerlord\.ButterLib','Crest.ButterLib'
    Write-Host "  $($d.Name) -> $newName"
    git mv $d.Name $newName
    $oldCs = "$newName\$($d.Name).csproj"
    $newCs = "$newName\$newName.csproj"
    if (Test-Path $oldCs) {
        git mv $oldCs $newCs
    }
}

cd ..
Write-Host "`n==> Final directory layout:"
Get-ChildItem -Recurse -Directory -Depth 2 | Where-Object { $_.Name -like 'Crest.*' -or $_.Name -like 'Bannerlord.*' } | ForEach-Object { Write-Host "  $($_.FullName)" }

Write-Host "`n==> git status (renames):"
git status --short

exit 0
