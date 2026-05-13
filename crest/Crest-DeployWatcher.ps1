# =====================================================================
# Crest-DeployWatcher.ps1 -- defer deploys until Bannerlord closes.
# =====================================================================
# Polls every 5 sec. When .runner\deploy-pending.txt exists AND no
# Bannerlord process is running, copies the freshly-built DLL into
# Modules\CREST and clears the pending marker. Lets the user keep
# playing battles back-to-back while code iterations queue up; the
# next time they exit the game, all pending deploys land at once.
#
# How a "pending deploy" gets created:
#   - Crest-Loop.ps1 (or any deploy step) detects DLL is locked and
#     instead writes the source DLL path to deploy-pending.txt.
#   - Or the user manually drops a path into deploy-pending.txt.
#
# Usage (run in its own PS window):
#   & C:\dev\bannerlord\crest\Crest-DeployWatcher.ps1
# =====================================================================

$ErrorActionPreference = 'Continue'

$pendingFile = 'C:\dev\bannerlord\crest\.runner\deploy-pending.txt'
$dst         = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client\Crest.Harmony.dll'
$pollSec     = 5

Write-Host ''
Write-Host '=========================================================' -ForegroundColor Cyan
Write-Host '  CREST Deploy Watcher (defers until Bannerlord exits)' -ForegroundColor Cyan
Write-Host '=========================================================' -ForegroundColor Cyan
Write-Host "  pending file:  $pendingFile"
Write-Host "  poll interval: ${pollSec}s"
Write-Host '  Ctrl+C to stop' -ForegroundColor DarkGray
Write-Host ''

while ($true) {
    Start-Sleep -Seconds $pollSec

    if (-not (Test-Path $pendingFile)) { continue }

    # Read the source path.
    $src = (Get-Content $pendingFile -Raw -ErrorAction SilentlyContinue).Trim()
    if (-not $src -or -not (Test-Path $src)) {
        # Stale or invalid pending marker -- purge it.
        Remove-Item $pendingFile -Force -ErrorAction SilentlyContinue
        Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] cleared invalid pending: $src" -ForegroundColor DarkYellow
        continue
    }

    # Bannerlord still running?
    $bl = Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue
    if ($bl) {
        # Sit tight; print a status line every minute or so to show liveness.
        if ((Get-Date).Second -lt $pollSec) {
            Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] waiting for Bannerlord (PID $($bl.Id)) to exit..." -ForegroundColor DarkGray
        }
        continue
    }

    # Clear to deploy.
    try {
        $srcSha = (Get-FileHash $src -Algorithm SHA256).Hash.Substring(0,12)
        $dstSha = if (Test-Path $dst) { (Get-FileHash $dst -Algorithm SHA256).Hash.Substring(0,12) } else { '<none>' }
        if ($srcSha -eq $dstSha) {
            Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] no-op: $srcSha already deployed" -ForegroundColor DarkGray
        } else {
            Copy-Item $src $dst -Force -ErrorAction Stop
            Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] DEPLOYED $dstSha -> $srcSha" -ForegroundColor Green
        }
        Remove-Item $pendingFile -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] deploy failed: $($_.Exception.Message)" -ForegroundColor Red
        # Don't clear the pending file -- try again next tick.
    }
}
