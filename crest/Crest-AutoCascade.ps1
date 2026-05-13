# =====================================================================
# Crest-AutoCascade.ps1 -- toggle the watcher's stage-B autobattle chain.
# =====================================================================
# When .runner\autocascade.on exists, the watcher's dev-mode chain
# automatically queues Crest-AutoBattle after every successful ready.
# Combined with the dev-mode chain stage A (postmortem -> ready), this
# makes the user's only required input the word "done" after a battle.
# Everything else -- postmortem, ready, next launch -- chains by itself.
#
# Usage:
#   crest AutoCascade On     -- enable
#   crest AutoCascade Off    -- disable
#   crest AutoCascade        -- show state
# =====================================================================

[CmdletBinding()]
param(
    [ValidateSet('On','Off','Status','')]
    [string]$State = 'Status'
)

$ErrorActionPreference = 'Continue'
$crestRoot = 'C:\dev\bannerlord\crest'
$sentinel  = Join-Path $crestRoot '.runner\autocascade.on'
New-Item -ItemType Directory -Path (Join-Path $crestRoot '.runner') -Force | Out-Null

Write-Host ''
Write-Host '== Crest AutoCascade ==' -ForegroundColor Cyan

switch ($State) {
    'On' {
        Set-Content -Path $sentinel -Value (Get-Date -Format 'o') -Encoding utf8
        Write-Host '  state:    ON' -ForegroundColor Green
        Write-Host '  effect:   after every postmortem the watcher will run' -ForegroundColor Gray
        Write-Host '            ready -> AutoBattle automatically. The user only' -ForegroundColor Gray
        Write-Host '            needs to play battles + type "done" between them.' -ForegroundColor Gray
    }
    'Off' {
        if (Test-Path $sentinel) { Remove-Item $sentinel -Force -ErrorAction SilentlyContinue }
        Write-Host '  state:    OFF' -ForegroundColor Yellow
    }
    default {
        $on = Test-Path $sentinel
        Write-Host ('  state:    ' + $(if ($on) { 'ON' } else { 'OFF' }))
        if (-not $on) {
            Write-Host '  toggle:   crest AutoCascade On' -ForegroundColor DarkGray
        }
    }
}
Write-Host ''
exit 0
