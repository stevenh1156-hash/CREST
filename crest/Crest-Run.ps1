# =====================================================================
# Crest-Run : the ONE master script.
# =====================================================================
# Usage:
#   & C:\dev\bannerlord\crest\Crest-Run.ps1
#
# What this does (in one paste):
#   0. Print START.md so the AI you paste output to has full project context.
#   1. Verify or auto-add the two Defender exclusions Crest needs (so deployed
#      DLLs aren't quarantined behind your back).
#   2. Hash-compare the source-built Crest.Harmony.dll vs the deployed one.
#      Surface any mismatch loudly.
#   3. Run all diag phases (status, snapshot, crash fetch, battle slice + map +
#      trails + collage + narrative) by invoking Crest-Diag.ps1 inline.
#   4. Print a manifest of every artifact in .runner\diag\ -- the AI can read
#      the text files directly; PNGs/JPGs need to be uploaded by the user.
#   5. Mirror EVERYTHING printed to .runner\diag\crest-run-output.txt, so the
#      user can copy-paste a single file back to the AI if scrollback is long.
#
# After this finishes you should have NOTHING else to do besides:
#   - if Defender was missing exclusions, restart the game once
#   - paste the output back to the AI
#   - if asked, upload any of the listed PNG/JPG vision artifacts
# =====================================================================

$ErrorActionPreference = 'Continue'

$crestRoot      = 'C:\dev\bannerlord\crest'
$startMdPath    = Join-Path $crestRoot 'START.md'
$diagDir        = Join-Path $crestRoot '.runner\diag'
$transcriptPath = Join-Path $diagDir   'crest-run-output.txt'
$crestDiagPs1   = Join-Path $crestRoot 'Crest-Diag.ps1'

$crestModuleDir = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'
$srcDll         = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Crest.Harmony.dll'
$dstDll         = "$crestModuleDir\bin\Win64_Shipping_Client\Crest.Harmony.dll"

New-Item -ItemType Directory -Path $diagDir -Force | Out-Null
if (Test-Path $transcriptPath) { Remove-Item $transcriptPath -Force }

# Both echo to host AND append to the transcript file.
function L($s, [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray) {
    if ($s -isnot [string]) { $s = ($s | Out-String).TrimEnd() }
    $s | Add-Content -Path $transcriptPath -Encoding utf8
    Write-Host $s -ForegroundColor $Color
}
function Hd($s) { L "" ; L "===== $s =====" ([System.ConsoleColor]::Cyan) }

# ---------------------------------------------------------------------
# 0. START.md (full context dump for AI handoff)
# ---------------------------------------------------------------------
Hd 'START.md (project context for AI)'
if (Test-Path $startMdPath) {
    Get-Content $startMdPath -Raw | ForEach-Object { L $_ }
} else {
    L "[Crest-Run] START.md missing at $startMdPath" Red
}

# ---------------------------------------------------------------------
# 1. Defender exclusions
# ---------------------------------------------------------------------
Hd 'Defender exclusions'
$wantPaths    = @('C:\dev\bannerlord', $crestModuleDir)
$wantProcesses= @('Mount and Blade II Bannerlord_BE.exe', 'Bannerlord.exe')
try {
    $pref = Get-MpPreference -ErrorAction Stop
    $havePaths     = @($pref.ExclusionPath)
    $haveProcesses = @($pref.ExclusionProcess)
    foreach ($p in $wantPaths) {
        if ($havePaths -contains $p) {
            L "  OK  path: $p" Green
        } else {
            L "  add path: $p" Yellow
            try { Add-MpPreference -ExclusionPath $p -ErrorAction Stop; L "    added." Green }
            catch { L "    FAILED to add (need admin?): $_" Red }
        }
    }
    foreach ($p in $wantProcesses) {
        if ($haveProcesses -contains $p) {
            L "  OK  process: $p" Green
        } else {
            L "  add process: $p" Yellow
            try { Add-MpPreference -ExclusionProcess $p -ErrorAction Stop; L "    added." Green }
            catch { L "    FAILED to add (need admin?): $_" Red }
        }
    }
} catch {
    L "  Get-MpPreference unavailable: $_" Red
}

# ---------------------------------------------------------------------
# 2. Source vs deployed DLL hash compare
# ---------------------------------------------------------------------
Hd 'DLL hash compare (source vs deployed)'
foreach ($p in @($srcDll, $dstDll)) {
    if (Test-Path $p) {
        $f = Get-Item $p
        $h = (Get-FileHash $p -Algorithm SHA256).Hash
        L ("  {0,12:N0} bytes  {1}  sha256={2}  {3}" -f $f.Length, $f.LastWriteTime, $h, $p)
    } else {
        L "  MISSING: $p" Red
    }
}
if ((Test-Path $srcDll) -and (Test-Path $dstDll)) {
    $sh = (Get-FileHash $srcDll -Algorithm SHA256).Hash
    $dh = (Get-FileHash $dstDll -Algorithm SHA256).Hash
    if ($sh -eq $dh) {
        L '  source matches deployed -- DLL is current' Green
    } else {
        L '  MISMATCH -- deployed DLL does NOT match latest source build' Red
        L '    (Defender quarantine? non-admin write? need to re-deploy.)' Red
    }
}

# ---------------------------------------------------------------------
# 3. Run Crest-Diag inline (status / snapshot / crash / battle / map /
#    trails / collage / narrative). It writes to .runner\diag\.
# ---------------------------------------------------------------------
Hd 'Crest-Diag (status + snapshot + crash + battle + vision)'
if (Test-Path $crestDiagPs1) {
    # Capture Crest-Diag's host output as well so it's in the transcript.
    & $crestDiagPs1 *>&1 | ForEach-Object {
        $line = $_
        if ($line -is [System.Management.Automation.ErrorRecord] -or
            $line -is [System.Management.Automation.WarningRecord] -or
            $line -is [System.Management.Automation.VerboseRecord] -or
            $line -is [System.Management.Automation.DebugRecord] -or
            $line -is [System.Management.Automation.InformationRecord]) {
            L ($line | Out-String).TrimEnd()
        } else {
            L $line
        }
    }
} else {
    L "  Crest-Diag.ps1 missing at $crestDiagPs1" Red
}

# ---------------------------------------------------------------------
# 4. Output manifest -- list everything in diag dir with sizes
# ---------------------------------------------------------------------
Hd 'Diag output manifest'
if (Test-Path $diagDir) {
    Get-ChildItem $diagDir -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object {
            L ("  {0,12:N0} bytes  {1}  {2}" -f $_.Length, $_.LastWriteTime, $_.Name)
        }
    $shotDir = Join-Path $diagDir 'screenshots'
    if (Test-Path $shotDir) {
        $count = (Get-ChildItem $shotDir -Filter 'shot-*.jpg' -File -ErrorAction SilentlyContinue).Count
        L ("  screenshots\: $count JPGs")
    }
}

# ---------------------------------------------------------------------
# 5. Done
# ---------------------------------------------------------------------
Hd 'done'
L "Transcript saved to $transcriptPath" Green
L "Paste either this console output OR the contents of crest-run-output.txt back to the AI." DarkGray
L "Vision artifacts (PNG/JPG) need to be uploaded separately if asked." DarkGray
