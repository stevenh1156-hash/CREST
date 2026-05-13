$ErrorActionPreference = 'Continue'
# Find the CheckIfSubModuleCanBeLoaded source in NuGet cache
$root = "$env:USERPROFILE\.nuget\packages"
Write-Host "==> Searching NuGet cache for CheckIfSubModuleCanBeLoaded"
$hits = Get-ChildItem -Recurse -File -Path $root -Filter '*.cs' -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -lt 500KB } |
    ForEach-Object {
        try {
            $c = [System.IO.File]::ReadAllText($_.FullName)
            if ($c -match 'CheckIfSubModuleCanBeLoaded') {
                $relativePath = $_.FullName.Substring($root.Length)
                Write-Host "  $relativePath"
                # Extract relevant lines
                $c -split "`n" | ForEach-Object { $i = 0 } {
                    $i++
                    if ($_ -match 'CheckIfSubModuleCanBeLoaded|dependency conflict|stability issues|loaded correctly') {
                        Write-Host ("    L{0,4}  {1}" -f $i, $_.Trim())
                    }
                }
            }
        } catch { }
    }
