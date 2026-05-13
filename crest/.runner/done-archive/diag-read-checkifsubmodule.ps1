$ErrorActionPreference = 'Continue'
$path = "$env:USERPROFILE\.nuget\packages\bannerlord.butr.shared\3.0.0.142\content\cs\netstandard2.0\Bannerlord.BUTR.Shared\Helpers\ModuleInfoHelper.cs"
if (Test-Path $path) {
    Write-Host "==> CheckIfSubModuleCanBeLoaded source (lines 180-260):"
    $lines = Get-Content $path
    for ($i = 179; $i -lt 260 -and $i -lt $lines.Count; $i++) {
        Write-Host ("{0,4}: {1}" -f ($i + 1), $lines[$i])
    }
}

# Also find where this method gets PATCHED in our SubModules
Write-Host ""
Write-Host "==> Where is CheckIfSubModuleCanBeLoaded patched/used in our forks:"
foreach ($fork in @('Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen')) {
    $repo = "C:\dev\bannerlord\$fork"
    if (Test-Path $repo) {
        $hits = Get-ChildItem -Recurse -File -Path $repo -Filter '*.cs' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notlike '*\bin\*' -and $_.FullName -notlike '*\obj\*' } |
            ForEach-Object {
                Select-String -Path $_.FullName -Pattern 'CheckIfSubModuleCanBeLoaded' -ErrorAction SilentlyContinue
            }
        if ($hits) {
            Write-Host "  $fork :"
            $hits | Select-Object -First 5 | ForEach-Object {
                Write-Host ("    {0}:{1}  {2}" -f ($_.Path | Split-Path -Leaf), $_.LineNumber, $_.Line.Trim())
            }
        }
    }
}
