# =====================================================================
# Crest-Cycle.ps1 -- one-command full iteration cycle.
# =====================================================================
# Composes: Audit -> Loop (build+sim) -> Deploy (if Loop green) -> Ready.
# Single command for a full pre-battle setup. Saves manually queueing
# each step.
#
# Usage:
#   & C:\dev\bannerlord\crest\Crest-Cycle.ps1
#   & C:\dev\bannerlord\crest\Crest-Cycle.ps1 -SkipAudit
#   & C:\dev\bannerlord\crest\Crest-Cycle.ps1 -SkipLoop      (just Deploy + Ready)
#
# Each step exits cycle early if it fails. Verdict written to console.
# =====================================================================

param(
    [switch]$SkipAudit,
    [switch]$SkipLoop,
    [switch]$SkipDeploy,
    [switch]$SkipReady
)

$ErrorActionPreference = 'Continue'
$crestRoot = 'C:\dev\bannerlord\crest'

function Banner($msg) {
    Write-Host ''
    Write-Host "===  $msg  ===" -ForegroundColor Cyan
}

# 1. Audit (CODE_INDEX.md refresh).
if (-not $SkipAudit) {
    Banner 'Audit'
    & (Join-Path $crestRoot 'Crest-Audit.ps1')
    if ($LASTEXITCODE -ne 0) { Write-Host '  audit failed' -ForegroundColor Red; exit 1 }
}

# 2. Loop (build + sim gate).
if (-not $SkipLoop) {
    Banner 'Loop (build + sim)'
    & (Join-Path $crestRoot 'Crest-Loop.ps1')
    if ($LASTEXITCODE -ne 0) {
        Write-Host '  loop failed -- aborting cycle' -ForegroundColor Red
        Write-Host '  see .runner\loop\latest.json for the verdict' -ForegroundColor Yellow
        exit 1
    }
}

# 3. Deploy (DLL copy to Modules\CREST). If Bannerlord is running OR
# the file is locked, drop a pending marker and let Crest-DeployWatcher
# apply it later.
if (-not $SkipDeploy) {
    Banner 'Deploy'
    $src = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll'
    $dst = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client\Crest.Harmony.dll'
    $pendingFile = 'C:\dev\bannerlord\crest\.runner\deploy-pending.txt'
    if (-not (Test-Path $src)) { Write-Host '  no src DLL' -ForegroundColor Red; exit 1 }
    $srcSha = (Get-FileHash $src -Algorithm SHA256).Hash.Substring(0,12)
    $dstSha = if (Test-Path $dst) { (Get-FileHash $dst -Algorithm SHA256).Hash.Substring(0,12) } else { '<none>' }

    if ($srcSha -eq $dstSha) {
        Write-Host "  no change ($srcSha)" -ForegroundColor DarkGray
    } else {
        # Pre-check: Bannerlord process running?
        $bl = Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue
        if ($bl) {
            Set-Content -Path $pendingFile -Value $src -Encoding utf8
            Write-Host "  Bannerlord is running (PID $($bl.Id)). Pending deploy queued." -ForegroundColor Yellow
            Write-Host "    pending: $pendingFile -> $src ($srcSha)" -ForegroundColor DarkYellow
            Write-Host '    (Crest-DeployWatcher will apply when Bannerlord exits.)' -ForegroundColor DarkYellow
        } else {
            try {
                Copy-Item $src $dst -Force -ErrorAction Stop
                Write-Host "  $dstSha -> $srcSha" -ForegroundColor Green
                # If a pending marker existed from before, it's now obsolete.
                if (Test-Path $pendingFile) { Remove-Item $pendingFile -Force -ErrorAction SilentlyContinue }
            } catch {
                # Locked despite no process? Mark pending and let watcher retry.
                Set-Content -Path $pendingFile -Value $src -Encoding utf8
                Write-Host "  deploy failed: $($_.Exception.Message)" -ForegroundColor Yellow
                Write-Host "    pending: $pendingFile -> $src ($srcSha)" -ForegroundColor DarkYellow
            }
        }
    }
}

# 4. Ready (recorder on, log rotate).
if (-not $SkipReady) {
    Banner 'Ready'
    & (Join-Path $crestRoot 'Crest-Ready.ps1')
}

Write-Host ''
Write-Host '== cycle complete -- launch Bannerlord and fight ==' -ForegroundColor Green
exit 0
