$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'

Write-Host '==> Step 1: branch BLSE to crest, commit the always-init patch' -ForegroundColor Cyan
Push-Location $blseRoot
try {
    $current = (& git branch --show-current 2>$null).Trim()
    Write-Host ('  current branch: ' + $current)
    if ($current -ne 'crest') {
        # Create or checkout crest branch
        $exists = (& git branch --list crest 2>$null).Trim()
        if ($exists) {
            & git checkout crest 2>&1 | Out-Null
        } else {
            & git checkout -b crest 2>&1 | Out-Null
        }
    }
    & git add -A 2>&1 | Out-Null
    $stat = (& git status --short 2>$null) -split "`n" | Where-Object { $_ }
    if ($stat) {
        & git commit -m 'feat(crest): always-init AppDomainManager (drop Epic-only guard)' 2>&1 | ForEach-Object { Write-Host ('    ' + $_) }
    } else {
        Write-Host '  nothing to commit'
    }
    $head = (& git rev-parse --short HEAD).Trim()
    Write-Host ('  HEAD ' + $head + ' on crest branch') -ForegroundColor Green
} finally { Pop-Location }

Write-Host ''
Write-Host '==> Step 2: rebuild AppDomainManager + Shared (env GameFolder set)' -ForegroundColor Cyan
$env:GameFolder = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
Push-Location $blseRoot
try {
    foreach ($p in @(
        'src\Bannerlord.BLSE.Shared\Bannerlord.BLSE.Shared.csproj',
        'src\Bannerlord.BLSE.Loaders.AppDomainManager\Bannerlord.BLSE.Loaders.AppDomainManager.csproj'
    )) {
        $name = (Split-Path $p -Leaf) -replace '\.csproj$', ''
        Write-Host ('  building ' + $name) -ForegroundColor Cyan
        $output = & dotnet build $p --configuration Release '-p:GenerateDocumentationFile=false' '-nowarn:CS1591' --nologo -v quiet 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host ('    FAIL ' + $name) -ForegroundColor Red
            $output | Where-Object { $_ -match '(error|Build FAILED)' } | Select-Object -First 6 | ForEach-Object { Write-Host ('      ' + $_) -ForegroundColor Red }
            exit 1
        }
        Write-Host ('    OK   ' + $name) -ForegroundColor Green
    }
} finally { Pop-Location }

Write-Host ''
Write-Host '==> Step 3: re-stage BLSE bin (picks up new AppDomainManager.dll) and redeploy' -ForegroundColor Cyan
$ok = Build-CrestBlse -StagingBlseBin 'C:\dev\bannerlord\crest\dist\full\bin\Win64_Shipping_Client' -SkipBuild
if (-not $ok) { exit 2 }
$ok = Deploy-CrestFullToBannerlord
if (-not $ok) { exit 3 }

Write-Host ''
Write-Host '==> Step 4: wipe BLSE_lasterror.log, repackage zip' -ForegroundColor Cyan
$err = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\bin\Win64_Shipping_Client\BLSE_lasterror.log'
if (Test-Path $err) { Remove-Item $err -Force; Write-Host '  cleared' }

$zip = New-CrestFullZip -Version '1.3.0'
if ($zip) { Write-Host ('  zip: ' + $zip) }

Write-Host ''
Write-Host '==> Done. Launch via Steam now — TaleWorlds.MountAndBlade.Launcher.exe will' -ForegroundColor Green
Write-Host '    invoke our patched AppDomainManager which always initializes BLSE.'
Write-Host '    blse.version should work in the dev console.'
