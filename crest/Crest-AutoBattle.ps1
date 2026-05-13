# =====================================================================
# Crest-AutoBattle.ps1 -- end-to-end battle automation.
# =====================================================================
# Goal: HERALD presses one button, the full cycle runs hands-free.
#
# Cycle:
#   1. If Bannerlord is not running -> launch it (continue save).
#   2. Wait for runtime.log activity (game loaded).
#   3. Bring Bannerlord to foreground.
#   4. Send the "engage nearest hostile" key (default Space) so the
#      player attacks whatever party they're already next to. The
#      precondition is the user left the save adjacent to an enemy.
#   5. Wait for battle-ended.txt sentinel (Phase A drop). Up to N sec.
#   6. Send Tab (open battle summary). Wait briefly.
#   7. Send Enter (close summary). Wait briefly.
#   8. Send Alt+F4 (close Bannerlord). DeployWatcher then applies any
#      pending DLL on exit.
#
# Uses Win32 SendInput for hardware-level keystroke injection so
# DirectInput-style games (Bannerlord) actually receive the keys.
# Plain SendKeys does not work for DirectInput.
#
# Usage:
#   crest AutoBattle               -> end-to-end run
#   crest AutoBattle -SkipLaunch   -> assume game already running
#   crest AutoBattle -DryRun       -> log what it would do, no input
# =====================================================================

param(
    [switch]$SkipLaunch,
    [switch]$DryRun,
    [int]$BattleTimeoutSec = 1800,    # 30 min cap on battle wait
    [int]$LoadTimeoutSec   = 120,     # 2 min for game to start logging
    [int]$DeployDelaySec   = 6,       # wait between Space and the deploy-skip Enter
    [switch]$NoDeploySkip             # set to leave the deploy screen alone
)

$ErrorActionPreference = 'Continue'

# Launch order (first hit wins). The plain Bannerlord.exe skips BLSE
# and ends up with NO mods loaded -- launchers below preserve mod load.
$launchCandidates = @(
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\bin\Win64_Shipping_Client\Bannerlord.BLSE.LauncherEx.exe',
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\bin\Win64_Shipping_Client\Bannerlord.BLSE.Launcher.exe',
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\bin\Win64_Shipping_Client\Bannerlord.exe'
)
$bannerlordExe   = $launchCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bannerlordExe) { $bannerlordExe = $launchCandidates[-1] }
$crestModuleRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'
$runtimeLog      = Join-Path $crestModuleRoot 'runtime.log'
$endedSentinel   = Join-Path $crestModuleRoot 'battle-ended.txt'

function Step($msg) { Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $msg" -ForegroundColor Cyan }
function Note($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }

Step 'Crest-AutoBattle starting'
if ($DryRun) { Note 'DRY RUN -- no input sent, no game launched' }

# ---------------------------------------------------------------------
# Win32 / SendInput types. Loaded once; defines a SendKeyTap helper.
# ---------------------------------------------------------------------
if (-not ('CrestInput' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class CrestInput {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT {
        public uint type;
        public KEYBDINPUT ki;
        public int padA; public int padB; public int padC; public int padD;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT {
        public ushort wVk; public ushort wScan; public uint dwFlags;
        public uint time; public IntPtr dwExtraInfo;
    }
    public const uint INPUT_KEYBOARD     = 1;
    public const uint KEYEVENTF_KEYUP    = 0x0002;
    public const uint KEYEVENTF_SCANCODE = 0x0008;

    public static void SendKeyTap(ushort scancode, int holdMs = 50) {
        var down = new INPUT { type = INPUT_KEYBOARD, ki = new KEYBDINPUT { wScan = scancode, dwFlags = KEYEVENTF_SCANCODE } };
        var up   = new INPUT { type = INPUT_KEYBOARD, ki = new KEYBDINPUT { wScan = scancode, dwFlags = KEYEVENTF_SCANCODE | KEYEVENTF_KEYUP } };
        SendInput(1, new[] { down }, Marshal.SizeOf(typeof(INPUT)));
        System.Threading.Thread.Sleep(holdMs);
        SendInput(1, new[] { up   }, Marshal.SizeOf(typeof(INPUT)));
    }

    // Hold modifier, tap key, release modifier.
    public static void SendKeyCombo(ushort modScancode, ushort keyScancode, int holdMs = 80) {
        var modDown = new INPUT { type = INPUT_KEYBOARD, ki = new KEYBDINPUT { wScan = modScancode, dwFlags = KEYEVENTF_SCANCODE } };
        var keyDown = new INPUT { type = INPUT_KEYBOARD, ki = new KEYBDINPUT { wScan = keyScancode, dwFlags = KEYEVENTF_SCANCODE } };
        var keyUp   = new INPUT { type = INPUT_KEYBOARD, ki = new KEYBDINPUT { wScan = keyScancode, dwFlags = KEYEVENTF_SCANCODE | KEYEVENTF_KEYUP } };
        var modUp   = new INPUT { type = INPUT_KEYBOARD, ki = new KEYBDINPUT { wScan = modScancode, dwFlags = KEYEVENTF_SCANCODE | KEYEVENTF_KEYUP } };
        SendInput(1, new[] { modDown }, Marshal.SizeOf(typeof(INPUT)));
        System.Threading.Thread.Sleep(20);
        SendInput(1, new[] { keyDown }, Marshal.SizeOf(typeof(INPUT)));
        System.Threading.Thread.Sleep(holdMs);
        SendInput(1, new[] { keyUp   }, Marshal.SizeOf(typeof(INPUT)));
        System.Threading.Thread.Sleep(20);
        SendInput(1, new[] { modUp   }, Marshal.SizeOf(typeof(INPUT)));
    }
}
'@
}

# Standard PS/2 scancodes (set 1).
$SC_SPACE = 0x39
$SC_TAB   = 0x0F
$SC_ENTER = 0x1C
$SC_F4    = 0x3E
$SC_LALT  = 0x38

function Bring-BannerlordForeground {
    try {
        $hWnd = [CrestInput]::FindWindow($null, 'Mount & Blade II: Bannerlord')
        if ($hWnd -eq [IntPtr]::Zero) { return $false }
        [CrestInput]::ShowWindow($hWnd, 9) | Out-Null   # SW_RESTORE
        [CrestInput]::SetForegroundWindow($hWnd) | Out-Null
        Start-Sleep -Milliseconds 400
        return $true
    } catch { return $false }
}

# ---------------------------------------------------------------------
# 1. Launch (if needed)
# ---------------------------------------------------------------------
$alreadyRunning = $null -ne (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)
if ($alreadyRunning) {
    Step 'Bannerlord already running -- skipping launch'
} elseif ($SkipLaunch) {
    Step 'SkipLaunch set -- bailing out'
    exit 0
} else {
    Step 'Launching Bannerlord (continue save)'
    if (-not (Test-Path $bannerlordExe)) {
        Write-Host "  ERROR: $bannerlordExe not found" -ForegroundColor Red
        exit 1
    }
    if (-not $DryRun) {
        # /continuesave loads the most recent save automatically.
        Start-Process -FilePath $bannerlordExe -ArgumentList '/continuesave' -WorkingDirectory (Split-Path -Parent $bannerlordExe) | Out-Null
    }
}

# ---------------------------------------------------------------------
# 2. Wait for runtime.log activity (game has loaded CREST).
# ---------------------------------------------------------------------
Step 'Waiting for game to finish loading (runtime.log activity)'
$loadStart  = Get-Date
$baselineLogSize = if (Test-Path $runtimeLog) { (Get-Item $runtimeLog).Length } else { 0 }
$gameReady = $false
while (((Get-Date) - $loadStart).TotalSeconds -lt $LoadTimeoutSec) {
    Start-Sleep -Seconds 3
    if (-not (Test-Path $runtimeLog)) { continue }
    $sz = (Get-Item $runtimeLog).Length
    if ($sz -gt $baselineLogSize + 1024) {
        # Check the LAST line is recent (last 60s); avoids matching stale.
        try {
            $tail = Get-Content $runtimeLog -Tail 1 -ErrorAction SilentlyContinue
            if ($tail -match '^\[(.+?)\]') {
                $ts = [DateTime]::Parse($Matches[1])
                if (((Get-Date) - $ts).TotalSeconds -lt 60) { $gameReady = $true; break }
            }
        } catch { }
    }
}
if (-not $gameReady) {
    Write-Host "  TIMEOUT: game did not produce runtime.log activity within ${LoadTimeoutSec}s" -ForegroundColor Yellow
    Note 'continuing anyway; user may need to position manually'
}
Step 'Game appears loaded'
Start-Sleep -Seconds 5    # let UI settle

# ---------------------------------------------------------------------
# 3-4. Foreground + send Space (engage default-targeted enemy).
#     (Precondition: save is parked next to a hostile party.)
# ---------------------------------------------------------------------
if (-not (Bring-BannerlordForeground)) {
    Note 'could not find Bannerlord window -- using best-effort key send'
}

Step 'Sending Space (engage)'
if (-not $DryRun) {
    [CrestInput]::SendKeyTap([ushort]$SC_SPACE, 80)
}

# After engage, the encounter / deploy screen comes up. Send Enter to start
# the battle directly (auto-deploy with default formations). Skipped if the
# user passed -NoDeploySkip.
if (-not $NoDeploySkip) {
    Step "Waiting ${DeployDelaySec}s, then sending Enter (skip deploy / start battle)"
    Start-Sleep -Seconds $DeployDelaySec
    Bring-BannerlordForeground | Out-Null
    if (-not $DryRun) {
        [CrestInput]::SendKeyTap([ushort]$SC_ENTER, 80)
    }
}

# ---------------------------------------------------------------------
# 5. Wait for battle-ended.txt sentinel.
# ---------------------------------------------------------------------
Step "Waiting for battle-ended sentinel (timeout ${BattleTimeoutSec}s)"
$battleStart = Get-Date
$battleDone  = $false
while (((Get-Date) - $battleStart).TotalSeconds -lt $BattleTimeoutSec) {
    if (Test-Path $endedSentinel) { $battleDone = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $battleDone) {
    Write-Host '  TIMEOUT waiting for battle-ended.txt -- aborting cleanup' -ForegroundColor Yellow
    exit 2
}
Step 'Battle ended sentinel detected'

# ---------------------------------------------------------------------
# 6-8. Tab -> Enter -> Alt+F4
# ---------------------------------------------------------------------
Bring-BannerlordForeground | Out-Null
Start-Sleep -Seconds 2

Step 'Sending Tab (battle summary)'
if (-not $DryRun) { [CrestInput]::SendKeyTap([ushort]$SC_TAB, 60) }
Start-Sleep -Seconds 2

Step 'Sending Enter (close summary)'
if (-not $DryRun) { [CrestInput]::SendKeyTap([ushort]$SC_ENTER, 60) }
Start-Sleep -Seconds 3

Step 'Sending Alt+F4 (close Bannerlord)'
if (-not $DryRun) { [CrestInput]::SendKeyCombo([ushort]$SC_LALT, [ushort]$SC_F4, 100) }
Start-Sleep -Seconds 2

Step 'AutoBattle complete -- HERALD continues from postmortem result'
exit 0
