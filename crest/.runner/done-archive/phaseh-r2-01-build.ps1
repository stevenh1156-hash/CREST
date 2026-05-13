# Phase H restart, step 1: verify current source state, then build all 4 forks.
#
# Background: namespace revert (Bannerlord.X.* / MCM.* in source, Crest.X
# AssemblyName) is already applied in working tree. v1.0.0 is tagged on
# each fork as a rollback safety net.
#
# This script:
#   1. Reports git status + branch + tag info on each fork
#   2. Confirms namespaces in source files match expectations
#   3. Runs Build-AllCrestRepos -Clean to compile everything fresh
#   4. Lists the produced DLLs

$ErrorActionPreference = 'Stop'

Write-Host "==> Step 1: git status / tag / branch per fork" -ForegroundColor Cyan
$repos = @(
    @{ Name='Harmony';      Path='C:\dev\bannerlord\Bannerlord.Harmony' },
    @{ Name='ButterLib';    Path='C:\dev\bannerlord\Bannerlord.ButterLib' },
    @{ Name='UIExtenderEx'; Path='C:\dev\bannerlord\Bannerlord.UIExtenderEx' },
    @{ Name='MCM';          Path='C:\dev\bannerlord\Bannerlord.MBOptionScreen' }
)
foreach ($r in $repos) {
    Write-Host ""
    Write-Host "---- $($r.Name) ----" -ForegroundColor White
    Push-Location $r.Path
    try {
        $branch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
        $sha = (git rev-parse --short HEAD 2>$null).Trim()
        $tags = (git tag --list 'v1*' 2>$null) -join ', '
        $dirty = (git status --short 2>$null) -split "`n" | Where-Object { $_ }
        Write-Host "  branch: $branch  sha: $sha  tags: $tags"
        Write-Host "  uncommitted: $($dirty.Count) files"
        $dirty | Select-Object -First 10 | ForEach-Object { Write-Host "    $_" }
    } finally { Pop-Location }
}

Write-Host ""
Write-Host "==> Step 2: namespace sanity checks in current source" -ForegroundColor Cyan
$expects = @(
    @{ File='C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\SubModule.cs';                                 Pattern='^namespace Bannerlord\.Harmony' },
    @{ File='C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\CrestConfig.cs';                                Pattern='^namespace Bannerlord\.Harmony' },
    @{ File='C:\dev\bannerlord\Bannerlord.ButterLib\src\Crest.ButterLib\ButterLibSubModule.cs';                     Pattern='^namespace Bannerlord\.ButterLib' },
    @{ File='C:\dev\bannerlord\Bannerlord.UIExtenderEx\src\Crest.UIExtenderEx\SubModule.cs';                        Pattern='^namespace Bannerlord\.UIExtenderEx' },
    @{ File='C:\dev\bannerlord\Bannerlord.MBOptionScreen\src\Crest.MCM\MCMSubModule.cs';                            Pattern='^namespace MCM' },
    @{ File='C:\dev\bannerlord\Bannerlord.MBOptionScreen\src\Crest.MCM.Bannerlord\MCMImplementationSubModule.cs';   Pattern='^namespace MCM\.Internal' },
    @{ File='C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI\MCMUISubModule.cs';                    Pattern='^namespace MCM\.UI' }
)
$nsClean = $true
foreach ($e in $expects) {
    if (-not (Test-Path $e.File)) {
        Write-Host "  MISSING: $($e.File)" -ForegroundColor Red
        $nsClean = $false
        continue
    }
    $hit = Select-String -Path $e.File -Pattern $e.Pattern -Quiet
    $color = if ($hit) { 'Green' } else { 'Red'; $nsClean = $false }
    Write-Host ("  {0,-90} {1}" -f (Split-Path $e.File -Leaf), (if ($hit) {'OK'} else {'MISMATCH'})) -ForegroundColor $color
}
if (-not $nsClean) {
    Write-Host "==> Namespace sanity check FAILED. Aborting before build." -ForegroundColor Red
    exit 2
}
Write-Host "==> Namespace sanity check passed." -ForegroundColor Green

Write-Host ""
Write-Host "==> Step 3: Build-AllCrestRepos -Clean" -ForegroundColor Cyan
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force
$ok = Build-AllCrestRepos -Clean
if (-not $ok) {
    Write-Host "==> BUILD FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "==> BUILD OK" -ForegroundColor Green

Write-Host ""
Write-Host "==> Step 4: list produced DLLs" -ForegroundColor Cyan
$outputs = @(
    'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll',
    'C:\dev\bannerlord\Bannerlord.ButterLib\src\Crest.ButterLib\bin\Release\net472\Crest.ButterLib.dll',
    'C:\dev\bannerlord\Bannerlord.ButterLib\src\Crest.ButterLib.Implementation\bin\Stable_Release\net472\Crest.ButterLib.Implementation.dll',
    'C:\dev\bannerlord\Bannerlord.UIExtenderEx\src\Crest.UIExtenderEx\bin\Release\netstandard2.0\Crest.UIExtenderEx.dll',
    'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src\Crest.MCM\bin\Release\netstandard2.0\Crest.MCM.dll',
    'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI\bin\Stable_Release\netstandard2.0\Crest.MCM.UI.dll'
)
foreach ($o in $outputs) {
    if (Test-Path $o) {
        $f = Get-Item $o
        Write-Host ("  {0,9:N1}KB  {1}" -f ($f.Length/1KB), ($f.FullName)) -ForegroundColor Green
    } else {
        Write-Host "  MISSING: $o" -ForegroundColor Red
    }
}
