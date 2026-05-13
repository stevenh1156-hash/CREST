# Same script as -29 but tolerant of git's "LF will be replaced by CRLF"
# stderr noise (which PowerShell otherwise treats as a hard error under
# ErrorActionPreference=Stop).
$ErrorActionPreference = 'Continue'

Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

$forks = @(
    @{ Name='Crest.Harmony';      Path='C:\dev\bannerlord\Bannerlord.Harmony';
       Msg = 'feat(crest): v1.1 - Phase H namespace revert (Bannerlord.Harmony) + RootNamespace alignment' },
    @{ Name='Crest.ButterLib';    Path='C:\dev\bannerlord\Bannerlord.ButterLib';
       Msg = 'feat(crest): v1.1 - Phase H namespace revert (Bannerlord.ButterLib) + RootNamespace alignment' },
    @{ Name='Crest.UIExtenderEx'; Path='C:\dev\bannerlord\Bannerlord.UIExtenderEx';
       Msg = 'feat(crest): v1.1 - Phase H namespace revert (Bannerlord.UIExtenderEx) + RootNamespace alignment' },
    @{ Name='Crest.MCM';          Path='C:\dev\bannerlord\Bannerlord.MBOptionScreen';
       Msg = 'feat(crest): v1.1 - Phase H namespace revert + MCM UI restore (RootNamespace=MCM.UI, ValidateLoadOrder neuter, try/catch wrappers, CrestEnabled gate)' }
)

Write-Host '==> Commit + tag v1.1.0 on each fork' -ForegroundColor Cyan
foreach ($f in $forks) {
    Write-Host ''
    Write-Host ('---- ' + $f.Name + ' ----')
    Push-Location $f.Path
    try {
        $branch = (& git rev-parse --abbrev-ref HEAD 2>$null).Trim()
        if ($branch -ne 'crest') {
            Write-Host ('  not on crest (branch=' + $branch + '), skipping') -ForegroundColor Red
            continue
        }
        $st = & git status --short 2>$null
        if (-not $st) {
            Write-Host '  working tree clean'
        } else {
            $cnt = @($st | Where-Object { $_ }).Count
            Write-Host ('  ' + $cnt + ' files changed; staging + committing')
            & git add -A 2>$null | Out-Null
            $commitOut = & git commit -m $f.Msg 2>&1
            $commitOut | Select-String -Pattern 'crest |master ' | ForEach-Object { Write-Host ('    ' + $_.Line) }
        }
        $existing = & git tag --list 'v1.1.0' 2>$null
        if ($existing) { & git tag -d v1.1.0 2>$null | Out-Null }
        & git tag -a v1.1.0 -m 'CREST v1.1.0 - Phase H complete (compatibility shims + MCM UI)' 2>$null | Out-Null
        $head = (& git rev-parse --short HEAD 2>$null).Trim()
        Write-Host ('  HEAD=' + $head + '  tag=v1.1.0') -ForegroundColor Green
    } finally { Pop-Location }
}

Write-Host ''
Write-Host '==> Package CREST-v1.1.0.zip' -ForegroundColor Cyan
$zip = New-CrestZip -Version '1.1.0' -OutDir 'C:\dev\bannerlord\crest\dist'

Write-Host ''
Write-Host '==> Modules.upstream-backup status' -ForegroundColor Cyan
$bk = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules.upstream-backup'
if (Test-Path $bk) {
    $size = (Get-ChildItem -Recurse -File $bk -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    Write-Host ('  preserved at ' + $bk + '  (' + [math]::Round($size/1MB, 1) + ' MB)')
    Write-Host '  delete manually when youre confident Phase H is stable'
}

Write-Host ''
Write-Host '==== v1.1 SHIP SUMMARY ====' -ForegroundColor Cyan
foreach ($f in $forks) {
    Push-Location $f.Path
    try {
        $head = (& git rev-parse --short HEAD 2>$null).Trim()
        $msg  = (& git log -1 --pretty=%s 2>$null).Trim()
        if ($msg.Length -gt 70) { $msg = $msg.Substring(0,70) + '...' }
        Write-Host ('  ' + $f.Name.PadRight(22) + ' ' + $head + '  ' + $msg) -ForegroundColor Green
    } finally { Pop-Location }
}
Write-Host ''
Write-Host '  Distributable: C:\dev\bannerlord\crest\dist\CREST-v1.1.0.zip'
