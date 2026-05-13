$ErrorActionPreference = 'Continue'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$installBin = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'

Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host '==> Build Crest.Harmony (CrestMessageStyle Phase O additions)' -ForegroundColor Cyan
$ok = Build-CrestRepo -Name Harmony
if (-not $ok) { Write-Host 'build FAILED' -ForegroundColor Red; exit 1 }

# Deploy ONLY Crest.Harmony.dll. Avoid full bundle redeploy that would
# trigger the MCM-build SubModule.xml-overwrite issue from earlier.
$src = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll'
$dst = Join-Path $installBin 'Crest.Harmony.dll'
Copy-Item $src $dst -Force
Write-Host ('   deployed Crest.Harmony.dll ts: ' + (Get-Item $dst).LastWriteTime.ToString('HH:mm:ss')) -ForegroundColor Green

# Confirm bin contents look healthy
$count = (Get-ChildItem $installBin -File).Count
$smXml = Join-Path $gameRoot 'Modules\CREST\SubModule.xml'
$lines = (Get-Content $smXml).Count
Write-Host ('   bin file count: ' + $count + '   SubModule.xml lines: ' + $lines)

# Update crest.json with the new flag (preserving user's other choices).
# Just trigger CrestConfig.WriteDefault by deleting the file -- next launch recreates with the new flag.
# Actually safer: preserve user's choices, just append the missing key. But the simplest is to
# delete + let CREST recreate on next launch with all flags defaulting to true.
$crestJson = Join-Path $gameRoot 'Modules\CREST\crest.json'
if (Test-Path $crestJson) {
    $content = Get-Content $crestJson -Raw
    if ($content -notmatch 'SuppressMainMenuMessages') {
        # Inject the new key right before AutoUnblock (or as last entry)
        $newContent = $content -replace '("MainMenuMonotone"\s*:\s*true,)', "`$1`n    `"SuppressMainMenuMessages`": true,"
        Set-Content $crestJson -Value $newContent -Encoding UTF8 -NoNewline
        Write-Host '   updated crest.json with SuppressMainMenuMessages=true' -ForegroundColor Green
    } else {
        Write-Host '   crest.json already has SuppressMainMenuMessages key'
    }
}

Write-Host ''
Write-Host '==> Now launch from Steam. Main-menu mod-load messages should be GONE.' -ForegroundColor Yellow
Write-Host '    They will be mirrored to: Modules\CREST\main-menu-messages.log' -ForegroundColor Yellow
Write-Host '    Once you start a campaign / battle, messages display normally again.' -ForegroundColor Yellow
