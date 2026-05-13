$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

$forks = @(
    @{ Name='Crest.Harmony';      Path='C:\dev\bannerlord\Bannerlord.Harmony';      Branch='crest';
       Msg = 'feat(crest): v1.3 - main-menu monotone color patch (CrestMessageStyle) + MainMenuMonotone gate' },
    @{ Name='Crest.ButterLib';    Path='C:\dev\bannerlord\Bannerlord.ButterLib';    Branch='crest';
       Msg = 'chore(crest): v1.3 - tag-only (no source changes since v1.1)' },
    @{ Name='Crest.UIExtenderEx'; Path='C:\dev\bannerlord\Bannerlord.UIExtenderEx'; Branch='crest';
       Msg = 'chore(crest): v1.3 - tag-only (no source changes since v1.1)' },
    @{ Name='Crest.MCM';          Path='C:\dev\bannerlord\Bannerlord.MBOptionScreen'; Branch='crest';
       Msg = 'feat(crest): v1.3 - CrestSettings MainMenuMonotone toggle in MCM Quality of Life group' },
    @{ Name='Bannerlord.BLSE';    Path='C:\dev\bannerlord\Bannerlord.BLSE';         Branch='crest';
       Msg = 'feat(crest): v1.3 - AppDomainManager always-init + HarmonyFinder CREST-bin fallback probe' }
)

Write-Host '==> Step 1: ensure each fork is on its crest branch + commit' -ForegroundColor Cyan
foreach ($f in $forks) {
    Write-Host ''
    Write-Host ('---- ' + $f.Name + ' ----')
    Push-Location $f.Path
    try {
        $current = (& git rev-parse --abbrev-ref HEAD 2>$null).Trim()
        if ($current -ne $f.Branch) {
            $existsOut = & git branch --list $f.Branch 2>$null
            $exists = $false
            if ($existsOut -ne $null) { $exists = ([string]$existsOut).Trim().Length -gt 0 }
            if ($exists) {
                & git checkout $f.Branch 2>&1 | Out-Null
            } else {
                & git checkout -b $f.Branch 2>&1 | Out-Null
            }
            Write-Host ('  switched to ' + $f.Branch)
        }
        $st = & git status --short 2>$null
        $cnt = 0
        if ($st) { $cnt = @($st | Where-Object { $_ }).Count }
        Write-Host ('  ' + $cnt + ' uncommitted files')
        if ($cnt -gt 0) {
            & git add -A 2>$null | Out-Null
            $commitOut = & git commit -m $f.Msg 2>&1
            $commitOut | Select-String -Pattern 'crest |master ' | ForEach-Object { Write-Host ('    ' + $_.Line) }
        }
        $existing = & git tag --list 'v1.3.0' 2>$null
        if ($existing) { & git tag -d v1.3.0 2>$null | Out-Null }
        & git tag -a v1.3.0 -m 'CREST v1.3.0 - BLSE bundled, slim stubs, monotone main menu' 2>$null | Out-Null
        $head = (& git rev-parse --short HEAD 2>$null).Trim()
        Write-Host ('  HEAD=' + $head + '  tag=v1.3.0') -ForegroundColor Green
    } finally { Pop-Location }
}

Write-Host ''
Write-Host '==> Step 2: package CREST-v1.3.0.zip' -ForegroundColor Cyan
$zip = New-CrestFullZip -Version '1.3.0'

Write-Host ''
Write-Host '==== v1.3.0 SHIP SUMMARY ====' -ForegroundColor Cyan
foreach ($f in $forks) {
    Push-Location $f.Path
    try {
        $head = (& git rev-parse --short HEAD 2>$null).Trim()
        $msg = (& git log -1 --pretty=%s 2>$null).Trim()
        if ($msg.Length -gt 70) { $msg = $msg.Substring(0,70) + '...' }
        Write-Host ('  ' + $f.Name.PadRight(22) + ' ' + $head + '  ' + $msg) -ForegroundColor Green
    } finally { Pop-Location }
}
Write-Host ''
Write-Host '  Distributable: C:\dev\bannerlord\crest\dist\CREST-v1.3.0.zip'
