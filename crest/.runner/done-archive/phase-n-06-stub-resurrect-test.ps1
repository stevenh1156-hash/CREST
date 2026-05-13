$ErrorActionPreference = 'Continue'

# Phase N: validate the install-time stub materialization in Unblock-CrestInstall.ps1.
# Delete two of the four stubs, run the script, verify both reappear with correct
# DefaultModule=true content.

Write-Host '==> Phase N: stub resurrect test' -ForegroundColor Cyan
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'

$victim1 = Join-Path $gameRoot 'Modules\Bannerlord.UIExtenderEx'
$victim2 = Join-Path $gameRoot 'Modules\Bannerlord.MBOptionScreen'

# ----- 1. Delete two stub folders -----
Write-Host ''
Write-Host '[1/3] Delete two stub folders' -ForegroundColor Cyan
foreach ($v in @($victim1, $victim2)) {
    if (Test-Path $v) {
        Remove-Item -Recurse -Force $v
        Write-Host ("  deleted " + (Split-Path $v -Leaf)) -ForegroundColor Yellow
    }
}
$stillExists = (Test-Path $victim1) -or (Test-Path $victim2)
if ($stillExists) { Write-Host '  ERROR: deletion failed' -ForegroundColor Red; exit 1 }
Write-Host '  OK -- both stubs removed' -ForegroundColor Green

# Confirm Doctor reports them as missing now (before resurrect)
Write-Host ''
Write-Host '[2/3] Pre-resurrect Doctor check (expect ERR for two stubs)' -ForegroundColor Cyan
$out = & 'C:\dev\bannerlord\crest\tools\doctor\Crest-Doctor.ps1' -Health 2>&1 | Out-String
$stubBlock = ($out -split "`n" | Where-Object { $_ -match 'stub|Stub modules' }) -join "`n"
Write-Host $stubBlock

# ----- 2. Run Unblock-CrestInstall.ps1 to materialize stubs -----
Write-Host ''
Write-Host '[3/3] Run Unblock-CrestInstall.ps1 (should resurrect stubs)' -ForegroundColor Cyan
& 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\Unblock-CrestInstall.ps1'

Write-Host ''
Write-Host '==> Verify resurrect' -ForegroundColor Cyan
$ok = $true
foreach ($v in @($victim1, $victim2)) {
    $xml = Join-Path $v 'SubModule.xml'
    if (-not (Test-Path $xml)) {
        Write-Host ("  MISSING " + (Split-Path $v -Leaf) + "\\SubModule.xml") -ForegroundColor Red
        $ok = $false
        continue
    }
    $content = Get-Content $xml -Raw
    $hasDefaultTrue = $content -match '<DefaultModule\s+value="true"'
    $size = (Get-Item $xml).Length
    if ($hasDefaultTrue) {
        Write-Host ("  OK " + (Split-Path $v -Leaf) + " ($size B, DefaultModule=true)") -ForegroundColor Green
    } else {
        Write-Host ("  WARN " + (Split-Path $v -Leaf) + " ($size B, but DefaultModule != true)") -ForegroundColor Yellow
        $ok = $false
    }
}

# Final Doctor pass
Write-Host ''
Write-Host '==> Post-resurrect Doctor (expect all four stubs OK)' -ForegroundColor Cyan
$out2 = & 'C:\dev\bannerlord\crest\tools\doctor\Crest-Doctor.ps1' -Health 2>&1 | Out-String
$stubBlock2 = ($out2 -split "`n" | Where-Object { $_ -match 'stub|Stub modules' }) -join "`n"
Write-Host $stubBlock2

if ($ok) { Write-Host ''; Write-Host '==> RESURRECT TEST PASSED' -ForegroundColor Green }
else     { Write-Host ''; Write-Host '==> RESURRECT TEST FAILED' -ForegroundColor Red }
