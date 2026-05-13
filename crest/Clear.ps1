# =====================================================================
# Crest Clear : wipe PowerShell history + clear the screen.
# =====================================================================
# Clears three kinds of "history" in PowerShell:
#   1. In-session command history       (Get-History / Clear-History)
#   2. PSReadLine in-session buffer     ([PSConsoleReadLine]::ClearHistory())
#   3. PSReadLine persistent file       ($host.PrivateData / HistorySavePath)
# Then clears the visible screen.
#
# Usage:
#   & C:\dev\bannerlord\crest\Clear.ps1
# =====================================================================

$ErrorActionPreference = 'SilentlyContinue'

# 1. In-session command history
try { Clear-History } catch { }

# 2. PSReadLine in-session buffer
try {
    if (Get-Module -ListAvailable -Name PSReadLine) {
        [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory()
    }
} catch { }

# 3. PSReadLine persistent history file (saved across sessions)
try {
    $opts = Get-PSReadlineOption
    if ($opts -and $opts.HistorySavePath -and (Test-Path $opts.HistorySavePath)) {
        Remove-Item -Path $opts.HistorySavePath -Force
    }
} catch { }

# Visible screen
Clear-Host
Write-Host '[Crest] history cleared.' -ForegroundColor DarkGray
