$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host '==> Build Harmony (CrestDiag + audit fixes)' -ForegroundColor Cyan
$ok = Build-CrestRepo -Name 'Harmony'
if (-not $ok) { exit 1 }

& 'C:\dev\bannerlord\crest\shims\flip-internals-public.ps1'
& 'C:\dev\bannerlord\crest\shims\generate-shims.ps1'

Write-Host ''
Write-Host '==> Reassemble + redeploy' -ForegroundColor Cyan
$ok = Build-CrestFullBundle -Version '1.3.1' -SkipBuild
if (-not $ok) { exit 2 }
$ok = Deploy-CrestFullToBannerlord
if (-not $ok) { exit 3 }

Write-Host ''
Write-Host '==> Verify CrestDiag is in deployed Crest.Harmony.dll' -ForegroundColor Cyan
$cecilPath = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'
Add-Type -Path $cecilPath
$dll = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client\Crest.Harmony.dll'
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dll)
try {
    $foundDiag = $false
    foreach ($t in $asm.MainModule.Types) {
        if ($t.Name -eq 'CrestDiag') { $foundDiag = $true; break }
    }
    if ($foundDiag) {
        Write-Host '  OK   Bannerlord.Harmony.CrestDiag' -ForegroundColor Green
    } else {
        Write-Host '  MISS CrestDiag' -ForegroundColor Red
    }
} finally { $asm.Dispose() }

Write-Host ''
Write-Host '==> Ship v1.3.1' -ForegroundColor Cyan
$forks = @(
    @{ Name='Crest.Harmony';      Path='C:\dev\bannerlord\Bannerlord.Harmony';        Branch='crest';
       Msg = 'fix(crest): v1.3.1 - audit fixes (CrestDiag helper, OnVideoStarted Type.EmptyTypes, logged AccessTools failures)' },
    @{ Name='Crest.MCM';          Path='C:\dev\bannerlord\Bannerlord.MBOptionScreen'; Branch='crest';
       Msg = 'chore(crest): v1.3.1 - tag-only (no source changes since v1.3)' },
    @{ Name='Bannerlord.BLSE';    Path='C:\dev\bannerlord\Bannerlord.BLSE';           Branch='crest';
       Msg = 'chore(crest): v1.3.1 - tag-only (no source changes since v1.3)' }
)
foreach ($f in $forks) {
    Write-Host ('---- ' + $f.Name + ' ----')
    Push-Location $f.Path
    try {
        $current = (& git rev-parse --abbrev-ref HEAD 2>$null).Trim()
        if ($current -ne $f.Branch) { & git checkout $f.Branch 2>&1 | Out-Null }
        $st = & git status --short 2>$null
        if ($st) {
            & git add -A 2>$null | Out-Null
            $commitOut = & git commit -m $f.Msg 2>&1
            $commitOut | Select-String -Pattern 'crest |master ' | ForEach-Object { Write-Host ('    ' + $_.Line) }
        } else {
            Write-Host '  no changes'
        }
        $existing = & git tag --list 'v1.3.1' 2>$null
        if ($existing) { & git tag -d v1.3.1 2>$null | Out-Null }
        & git tag -a v1.3.1 -m 'CREST v1.3.1 - Phase P audit fixes' 2>$null | Out-Null
        $head = (& git rev-parse --short HEAD 2>$null).Trim()
        Write-Host ('  HEAD=' + $head + '  tag=v1.3.1') -ForegroundColor Green
    } finally { Pop-Location }
}

$zip = New-CrestFullZip -Version '1.3.1'
Write-Host ''
Write-Host ('==> Done. Zip: ' + $zip) -ForegroundColor Green
