# =====================================================================
# Crest-SourceWatch.ps1 -- auto-build daemon.
# =====================================================================
# Watches the Crest.Harmony source tree for *.cs Created/Changed/Deleted
# events. On any change (debounced 2 sec), drops a queue script that
# runs Crest-Loop.ps1 against the harmony csproj. Closes the manual
# "queue a build after editing" round-trip -- save, walk away, the
# new DLL is deployed within ~5 sec.
#
# Run in its own admin PowerShell window:
#   & C:\dev\bannerlord\crest\Crest-SourceWatch.ps1
#
# Stop with Ctrl+C. The watcher process is the only listener; killing
# this script unsubscribes cleanly.
# =====================================================================

$ErrorActionPreference = 'Continue'

$watchRoots = @(
    'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony',
    'C:\dev\bannerlord\Bannerlord.ButterLib\src\Crest.ButterLib',
    'C:\dev\bannerlord\Bannerlord.Harmony\sim\Crest.Harmony.Sim'
)
$queueDir   = 'C:\dev\bannerlord\crest\.runner\queue'
$debounceMs = 2000

Write-Host ''
Write-Host '=========================================================' -ForegroundColor Cyan
Write-Host '  CREST Source Watcher (auto-build on save)' -ForegroundColor Cyan
Write-Host '=========================================================' -ForegroundColor Cyan
foreach ($r in $watchRoots) {
    if (Test-Path $r) { Write-Host "  watching: $r" -ForegroundColor Gray }
    else               { Write-Host "  skipped:  $r (not found)" -ForegroundColor DarkGray }
}
Write-Host '  press Ctrl+C to stop' -ForegroundColor DarkGray
Write-Host ''

$watchers = @()
$lastEvent = [DateTime]::MinValue
$pendingPath = ''

foreach ($root in $watchRoots) {
    if (-not (Test-Path $root)) { continue }
    $w = New-Object System.IO.FileSystemWatcher
    $w.Path = $root
    $w.Filter = '*.cs'
    $w.IncludeSubdirectories = $true
    $w.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor `
                       [System.IO.NotifyFilters]::FileName -bor `
                       [System.IO.NotifyFilters]::CreationTime
    $w.EnableRaisingEvents = $true

    $action = {
        $script:lastEvent = Get-Date
        $script:pendingPath = $Event.SourceEventArgs.FullPath
    }
    Register-ObjectEvent -InputObject $w -EventName Created -Action $action | Out-Null
    Register-ObjectEvent -InputObject $w -EventName Changed -Action $action | Out-Null
    Register-ObjectEvent -InputObject $w -EventName Renamed -Action $action | Out-Null
    $watchers += $w
}

# Main loop: poll for debounce expiry, fire build if pending.
while ($true) {
    Start-Sleep -Milliseconds 500
    if ($lastEvent -eq [DateTime]::MinValue) { continue }
    $age = (Get-Date) - $lastEvent
    if ($age.TotalMilliseconds -lt $debounceMs) { continue }

    # Fire it.
    $shortPath = if ($pendingPath) { Split-Path -Leaf $pendingPath } else { '<unknown>' }
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $qfile = Join-Path $queueDir "agent-autobuild-$stamp.ps1"

    $body = @"
# Auto-queued by Crest-SourceWatch.ps1
# trigger file: $shortPath
`$ErrorActionPreference = 'Continue'
& C:\dev\bannerlord\crest\Crest-Loop.ps1
exit `$LASTEXITCODE
"@
    try {
        New-Item -ItemType Directory -Path $queueDir -Force | Out-Null
        Set-Content -Path $qfile -Value $body -Encoding utf8
        Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] -> $shortPath  queued $(Split-Path -Leaf $qfile)" -ForegroundColor Yellow
    } catch {
        Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] queue write failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Reset.
    $lastEvent = [DateTime]::MinValue
    $pendingPath = ''
}
