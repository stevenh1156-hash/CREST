# Move *.upstream-backup folders OUT of Modules\ so the launcher stops scanning them.
# The launcher reads <Id> from each SubModule.xml; our renamed folders still have
# the original Bannerlord.X ids inside, so the launcher sees them as duplicate
# entries to our stubs. Move them to a sibling folder.

$ErrorActionPreference = 'Stop'

$gameRoot      = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$gameModules   = Join-Path $gameRoot 'Modules'
$backupParent  = Join-Path $gameRoot 'Modules.upstream-backup'

if (-not (Test-Path $backupParent)) {
    New-Item -ItemType Directory -Path $backupParent | Out-Null
    Write-Host "==> Created $backupParent" -ForegroundColor Cyan
}

$names = @('Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen')

Write-Host ""
Write-Host "==> Moving *.upstream-backup folders out of Modules\" -ForegroundColor Cyan
foreach ($n in $names) {
    $src = Join-Path $gameModules ($n + '.upstream-backup')
    $dst = Join-Path $backupParent $n
    if (-not (Test-Path $src)) {
        Write-Host "  no backup for $n (skip)" -ForegroundColor DarkGray
        continue
    }
    if (Test-Path $dst) {
        Write-Host "  removing existing destination $dst" -ForegroundColor DarkGray
        Remove-Item -Recurse -Force $dst
    }
    Move-Item -Path $src -Destination $dst
    Write-Host ("  moved {0,-30} -> {1}" -f ($n + '.upstream-backup'), $dst) -ForegroundColor Green
}

Write-Host ""
Write-Host "==> Final state of Modules\ (relevant entries)" -ForegroundColor Cyan
Get-ChildItem $gameModules -Directory | Where-Object {
    $_.Name -in $names -or $_.Name -like 'CREST*'
} | Sort-Object Name | ForEach-Object {
    $sm = Join-Path $_.FullName 'SubModule.xml'
    $kind = '?'
    if (Test-Path $sm) {
        $c = Get-Content $sm -Raw
        if ($c -match 'CREST stub') { $kind = 'STUB' }
        elseif ($c -match '<Id value="CREST"') { $kind = 'CREST' }
        else { $kind = 'UPSTREAM' }
    }
    Write-Host ("  [{0,-8}] {1}" -f $kind, $_.Name)
}

Write-Host ""
Write-Host "==> Check no upstream-backup remnants remain in Modules\" -ForegroundColor Cyan
$leftovers = Get-ChildItem $gameModules -Directory | Where-Object { $_.Name -like '*upstream-backup*' }
if ($leftovers) {
    foreach ($l in $leftovers) {
        Write-Host ("  STILL THERE: {0}" -f $l.Name) -ForegroundColor Red
    }
} else {
    Write-Host "  all clear" -ForegroundColor Green
}

Write-Host ""
Write-Host "==> Backups now at: $backupParent" -ForegroundColor Cyan
Get-ChildItem $backupParent -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $size = (Get-ChildItem -Recurse -File $_.FullName -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    Write-Host ("  {0,-30} {1,9:N1}KB" -f $_.Name, ($size/1KB))
}

Write-Host ""
Write-Host "==> Done. Relaunch the game and check the launcher mod list." -ForegroundColor Green
