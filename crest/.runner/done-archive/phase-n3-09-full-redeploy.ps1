$ErrorActionPreference = 'Continue'

Write-Host '==> Full CREST bin redeploy (from existing staging)' -ForegroundColor Cyan

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$staging = 'C:\dev\bannerlord\crest\dist\CREST'
$installCrest = Join-Path $gameRoot 'Modules\CREST'
$installBin = Join-Path $installCrest 'bin\Win64_Shipping_Client'

if (-not (Test-Path "$staging\bin\Win64_Shipping_Client")) {
    Write-Host '   ERROR: staging is empty -- need to run Build-CrestBundle first' -ForegroundColor Red
    Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force
    Build-CrestBundle -SkipBuild | Out-Null
}

# Wipe + repopulate the install bin from staging
if (Test-Path $installBin) {
    Write-Host ('   wiping ' + $installBin)
    Remove-Item -Recurse -Force $installBin
}
New-Item -ItemType Directory -Path $installBin -Force | Out-Null

Copy-Item -Path (Join-Path $staging 'bin\Win64_Shipping_Client\*') -Destination $installBin -Recurse -Force

$count = (Get-ChildItem $installBin -File).Count
Write-Host ('   restored ' + $count + ' files') -ForegroundColor Green

# Show critical files
Write-Host ''
Write-Host '==> Critical DLLs check' -ForegroundColor Cyan
foreach ($n in '0Harmony.dll','Crest.Harmony.dll','Crest.ButterLib.dll','Crest.MCM.dll','CREST.v1.4.1.dll','Bannerlord.Harmony.dll','Mono.Cecil.dll') {
    $p = Join-Path $installBin $n
    if (Test-Path $p) {
        Write-Host ('   OK  ' + $n + '  (' + ([math]::Round((Get-Item $p).Length/1KB)) + ' KB)') -ForegroundColor Green
    } else {
        Write-Host ('   MISSING ' + $n) -ForegroundColor Red
    }
}

# Smoke test
Write-Host ''
Write-Host '==> Launch test (Steam path)' -ForegroundColor Cyan
$bin = Join-Path $gameRoot 'bin\Win64_Shipping_Client'
$proc = Start-Process -FilePath (Join-Path $bin 'TaleWorlds.MountAndBlade.Launcher.exe') -WorkingDirectory $bin -PassThru
Start-Sleep -Seconds 14
$proc.Refresh()
if ($proc.HasExited) { Write-Host ('   EXITED code=' + $proc.ExitCode) -ForegroundColor Red }
else { Write-Host ('   running ' + $proc.Modules.Count + ' modules') -ForegroundColor Green; Stop-Process -Id $proc.Id -Force }

Write-Host ''
Write-Host '==> Restored. Try launching the game from Steam.' -ForegroundColor Yellow
