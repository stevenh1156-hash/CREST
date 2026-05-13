# =====================================================================
# Crest-DevMode.ps1 -- toggle the agent-side dev-mode sentinel.
# =====================================================================
# When the file C:\dev\bannerlord\crest\.runner\dev-mode.on exists,
# the AI agent's standing-order rule (START.md section 0.3) is:
#   "auto-queue Crest-Ready.ps1 at the end of every response."
#
# That keeps the system primed for a battle on every interaction so
# the user can drop into Bannerlord any time without saying "ready"
# first. Postmortem ("done") still runs the full diagnostic, archives
# the recording, and disables record.on / verbose.on -- on the next
# agent response, the dev-mode rule re-enables them again.
#
# Usage:
#   & C:\dev\bannerlord\crest\Crest-DevMode.ps1 -State On
#   & C:\dev\bannerlord\crest\Crest-DevMode.ps1 -State Off
#   & C:\dev\bannerlord\crest\Crest-DevMode.ps1                (status)
# =====================================================================

[CmdletBinding()]
param(
    [ValidateSet('On','Off','Status','')]
    [string]$State = 'Status'
)

$ErrorActionPreference = 'Continue'

$crestRoot = 'C:\dev\bannerlord\crest'
$runner    = Join-Path $crestRoot '.runner'
$sentinel  = Join-Path $runner 'dev-mode.on'

New-Item -ItemType Directory -Path $runner -Force | Out-Null

Write-Host ''
Write-Host '== Crest DevMode ==' -ForegroundColor Cyan

switch ($State) {
    'On' {
        $stamp = (Get-Date).ToString('o')
        Set-Content -Path $sentinel -Value $stamp -Encoding utf8
        Write-Host '  state:    ON' -ForegroundColor Green
        Write-Host "  sentinel: $sentinel" -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  Behavior: the AI agent will queue Crest-Ready.ps1 at the end' -ForegroundColor Gray
        Write-Host '  of every response. To disable, run:' -ForegroundColor Gray
        Write-Host '    Crest.ps1 -Mode DevMode -Arg Off' -ForegroundColor Yellow
    }
    'Off' {
        if (Test-Path $sentinel) {
            Remove-Item $sentinel -Force -ErrorAction SilentlyContinue
            Write-Host '  state:    OFF (sentinel removed)' -ForegroundColor Yellow
        } else {
            Write-Host '  state:    OFF (was not on)' -ForegroundColor DarkGray
        }
    }
    default {
        if (Test-Path $sentinel) {
            $since = (Get-Item $sentinel).LastWriteTime
            Write-Host '  state:    ON' -ForegroundColor Green
            Write-Host "  since:    $since" -ForegroundColor DarkGray
            Write-Host "  sentinel: $sentinel" -ForegroundColor DarkGray
        } else {
            Write-Host '  state:    OFF' -ForegroundColor DarkGray
            Write-Host '  toggle:   Crest.ps1 -Mode DevMode -Arg On' -ForegroundColor DarkGray
        }
    }
}
Write-Host ''
exit 0
