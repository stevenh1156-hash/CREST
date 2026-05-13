$ErrorActionPreference = 'Stop'

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

Write-Host '==> Step 1: review uncommitted changes per fork' -ForegroundColor Cyan
foreach ($f in $forks) {
    Write-Host ''
    Write-Host ('---- ' + $f.Name + ' ----')
    Push-Location $f.Path
    try {
        $st = git status --short
        $cnt = 0
        if ($st) { $cnt = @($st | Where-Object { $_ }).Count }
        Write-Host ('  ' + $cnt + ' uncommitted files')
        $st | Select-Object -First 6 | ForEach-Object { Write-Host ('    ' + $_) }
    } finally { Pop-Location }
}

Write-Host ''
Write-Host '==> Step 2: commit + tag v1.1.0 on each fork' -ForegroundColor Cyan
foreach ($f in $forks) {
    Write-Host ''
    Write-Host ('---- committing ' + $f.Name + ' ----')
    Push-Location $f.Path
    try {
        $branch = (git rev-parse --abbrev-ref HEAD).Trim()
        if ($branch -ne 'crest') {
            Write-Host ('  not on crest branch (currently ' + $branch + '), skipping') -ForegroundColor Red
            continue
        }
        $st = git status --short
        if (-not $st) {
            Write-Host '  working tree clean (nothing to commit)'
        } else {
            git add -A 2>&1 | Out-Null
            git commit -m $f.Msg 2>&1 | ForEach-Object { Write-Host ('    ' + $_) }
        }
        $existing = git tag --list 'v1.1.0'
        if ($existing) { git tag -d v1.1.0 2>&1 | Out-Null }
        git tag -a v1.1.0 -m 'CREST v1.1.0 - Phase H complete (compatibility shims + MCM UI)' 2>&1 | Out-Null
        $head = git rev-parse --short HEAD
        Write-Host ('  HEAD: ' + $head + '  tag: v1.1.0') -ForegroundColor Green
    } finally { Pop-Location }
}

Write-Host ''
Write-Host '==> Step 3: package CREST-v1.1.0.zip' -ForegroundColor Cyan
$zip = New-CrestZip -Version '1.1.0' -OutDir 'C:\dev\bannerlord\crest\dist'
if ($zip) { Write-Host ('  zip ready: ' + $zip) -ForegroundColor Green }

Write-Host ''
Write-Host '==> Step 4: status of Modules.upstream-backup' -ForegroundColor Cyan
$backupRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules.upstream-backup'
if (Test-Path $backupRoot) {
    $size = (Get-ChildItem -Recurse -File $backupRoot -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    Write-Host ('  preserved at ' + $backupRoot + '  (' + [math]::Round($size/1MB, 1) + ' MB) - delete manually when confident')
} else {
    Write-Host '  no backup folder present'
}

Write-Host ''
Write-Host '==== v1.1 SHIP SUMMARY ====' -ForegroundColor Cyan
foreach ($f in $forks) {
    Push-Location $f.Path
    try {
        $head = git rev-parse --short HEAD
        $msg = (git log -1 --pretty=%s).Trim()
        if ($msg.Length -gt 60) { $msg = $msg.Substring(0,60) + '...' }
        Write-Host ('  ' + $f.Name.PadRight(22) + ' ' + $head + '  ' + $msg) -ForegroundColor Green
    } finally { Pop-Location }
}
Write-Host ''
Write-Host '  Distributable: C:\dev\bannerlord\crest\dist\CREST-v1.1.0.zip'
