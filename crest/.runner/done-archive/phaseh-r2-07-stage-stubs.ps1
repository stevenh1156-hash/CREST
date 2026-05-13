# Phase H restart, step 5: stage stub Bannerlord.X module folders into the
# game's Modules\, after archiving any existing upstream BUTR module of the
# same name. This makes the user's install look like:
#   Modules\
#     CREST\                            (full implementation + shims)
#     Bannerlord.Harmony\               (CREST stub - SubModule.xml only)
#     Bannerlord.ButterLib\             (CREST stub)
#     Bannerlord.UIExtenderEx\          (CREST stub)
#     Bannerlord.MBOptionScreen\        (CREST stub)
#
# Existing upstream folders (if any) are renamed to *.upstream-backup so the
# user can restore them if Phase H needs rolling back.

$ErrorActionPreference = 'Stop'

$gameModules = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules'
$stubsRoot   = 'C:\dev\bannerlord\crest\stubs'

$stubs = @(
    'Bannerlord.Harmony',
    'Bannerlord.ButterLib',
    'Bannerlord.UIExtenderEx',
    'Bannerlord.MBOptionScreen'
)

Write-Host "==> Step 1: archive existing upstream module folders" -ForegroundColor Cyan
foreach ($name in $stubs) {
    $existing = Join-Path $gameModules $name
    $backup   = Join-Path $gameModules ($name + '.upstream-backup')
    if (Test-Path $existing) {
        # Detect whether this is already our stub (a SubModule.xml that mentions "CREST stub")
        $smXml = Join-Path $existing 'SubModule.xml'
        $isOurs = $false
        if (Test-Path $smXml) {
            $content = Get-Content $smXml -Raw
            if ($content -match 'CREST stub') { $isOurs = $true }
        }
        if ($isOurs) {
            Write-Host "  skip   $name  (already a CREST stub)" -ForegroundColor DarkGray
            continue
        }
        if (Test-Path $backup) {
            Write-Host "  reuse  $name  (existing $($name + '.upstream-backup') already present)" -ForegroundColor Yellow
            Remove-Item -Recurse -Force $existing
        } else {
            Write-Host "  rename $name  ->  $name.upstream-backup" -ForegroundColor Yellow
            Rename-Item -Path $existing -NewName ($name + '.upstream-backup')
        }
    } else {
        Write-Host "  none   $name  (not installed)" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "==> Step 2: copy stub folders into game Modules\" -ForegroundColor Cyan
foreach ($name in $stubs) {
    $src = Join-Path $stubsRoot $name
    $dst = Join-Path $gameModules $name
    if (-not (Test-Path $src)) {
        Write-Host "  MISSING source: $src" -ForegroundColor Red
        continue
    }
    if (Test-Path $dst) {
        Remove-Item -Recurse -Force $dst
    }
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Copy-Item -Recurse -Path (Join-Path $src '*') -Destination $dst -Force
    $size = (Get-ChildItem -Recurse -File $dst | Measure-Object -Property Length -Sum).Sum
    Write-Host ("  OK     {0}  ({1} bytes)" -f $name, $size) -ForegroundColor Green
}

Write-Host ""
Write-Host "==> Step 3: final state of relevant Modules\ entries" -ForegroundColor Cyan
Get-ChildItem $gameModules -Directory | Where-Object {
    $_.Name -in $stubs -or $_.Name -like '*upstream-backup' -or $_.Name -eq 'CREST'
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
Write-Host "==> Phase H step 5 OK." -ForegroundColor Green
Write-Host "    Stubs are deployed. The game's Modules\ now references CREST for"
Write-Host "    Harmony/ButterLib/UIExtenderEx/MCM. Upstream BUTR folders moved to"
Write-Host "    .upstream-backup so they don't conflict and can be restored if needed."
