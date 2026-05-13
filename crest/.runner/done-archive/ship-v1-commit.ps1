$ErrorActionPreference = 'Continue'

# Step 1: review uncommitted changes per fork
$repos = @(
    @{ Name='Crest.Harmony';       Path='C:\dev\bannerlord\Bannerlord.Harmony';
       CommitMsg=@"
feat(crest): v1.0 - Phase J + Phase L Stage 1 + ValidateLoadOrder hardening

- Add CrestConfig (public) with Modules\CREST\crest.json file format
  for per-sub-module enable flags. Auto-writes a default file on first
  access with all flags = true. Tiny regex-based JSON parser keeps the
  fork independent of Newtonsoft.Json which loads later.

- Add CrestQuickStart (Phase J): Harmony-patches
  TaleWorlds.MountAndBlade.VideoPlaybackState.OnVideoStarted to
  immediately invoke OnVideoFinished, skipping the
  Videos/TWLogo_and_Partners.ivf intro. Faction main-menu loops and
  in-game cinematics keep playing normally. Toggle via
  CREST_SKIP_INTRO=0 env or 'SkipIntroVideo' in crest.json.

- Wire CrestQuickStart.Apply() in SubModule.OnSubModuleLoad.
"@ },
    @{ Name='Crest.ButterLib';     Path='C:\dev\bannerlord\Bannerlord.ButterLib';
       CommitMsg=@"
feat(crest): v1.0 - Phase L Stage 1 gating + ValidateLoadOrder neutering

- ButterLibSubModule.OnSubModuleLoad now early-returns if
  Crest.Harmony.CrestConfig.IsEnabled('ButterLib') is false. Reflection
  call avoids compile-time cross-fork dependency.

- ValidateLoadOrder() call in ctor commented out. Without this, the
  validator can't satisfy upstream-style depended-module declarations
  under CREST's bundled-everything model and falls into MessageBox.Show
  -> Environment.Exit(1).
"@ },
    @{ Name='Crest.UIExtenderEx';  Path='C:\dev\bannerlord\Bannerlord.UIExtenderEx';
       CommitMsg=@"
feat(crest): v1.0 - ValidateLoadOrder neutering

ValidateLoadOrder() call in SubModule ctor commented out. Without this,
the validator surfaces 'dependency conflict' against CREST when consumer
mods are in the modlist.
"@ },
    @{ Name='Crest.MCM';           Path='C:\dev\bannerlord\Bannerlord.MBOptionScreen';
       CommitMsg=@"
feat(crest): v1.0 - Phase L Stage 1 gating in MCM SubModules

MCMSubModule and MCMImplementationSubModule's OnSubModuleLoad now
early-return if Crest.Harmony.CrestConfig.IsEnabled('MCM') / 'MCMBasicImplementation'
is false. Reflection call avoids compile-time cross-fork dependency.

(MCMUISubModule's ValidateLoadOrder still active; that path is gated
behind Phase D.4 deep-diagnosis for v1.1.)
"@ }
)

Write-Host "==> Step 1: review uncommitted changes per fork" -ForegroundColor Cyan
foreach ($r in $repos) {
    Write-Host ""
    Write-Host "---- $($r.Name) ($($r.Path)) ----" -ForegroundColor DarkCyan
    Push-Location $r.Path
    try {
        $status = git status --short 2>$null
        $count = ($status | Where-Object { $_ } | Measure-Object).Count
        Write-Host "  $count uncommitted files"
        $status | Select-Object -First 12 | ForEach-Object { Write-Host "    $_" }
        if ($count -gt 12) { Write-Host ("    ... and {0} more" -f ($count - 12)) }
    } finally { Pop-Location }
}

# Step 2: commit each fork on the crest branch
Write-Host ""
Write-Host "==> Step 2: commit each fork" -ForegroundColor Cyan
foreach ($r in $repos) {
    Write-Host ""
    Write-Host "---- committing $($r.Name) ----" -ForegroundColor DarkCyan
    Push-Location $r.Path
    try {
        $branch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
        if ($branch -ne 'crest') {
            Write-Host "  WARNING: not on crest branch (currently '$branch'), skipping" -ForegroundColor Yellow
            continue
        }
        $status = git status --short 2>$null
        if (-not $status) {
            Write-Host "  clean - nothing to commit"
            continue
        }
        git add -A 2>&1 | Out-Null
        # Use a temp file for the multi-line commit message
        $tmpFile = [System.IO.Path]::GetTempFileName()
        try {
            Set-Content -Path $tmpFile -Value $r.CommitMsg -Encoding UTF8
            git commit -F $tmpFile 2>&1 | ForEach-Object { Write-Host "  $_" }
        } finally {
            Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
        }
        $newSha = (git rev-parse --short HEAD 2>$null).Trim()
        Write-Host "  HEAD now $newSha" -ForegroundColor Green
    } finally { Pop-Location }
}

# Step 3: also commit the crest meta-repo if it's git-tracked
Write-Host ""
Write-Host "==> Step 3: check crest meta-tree git state" -ForegroundColor Cyan
Push-Location 'C:\dev\bannerlord\crest'
try {
    if (Test-Path .git) {
        $status = git status --short 2>$null
        $count = ($status | Where-Object { $_ } | Measure-Object).Count
        Write-Host "  $count uncommitted files in crest/"
        if ($count -gt 0) {
            git add -A 2>&1 | Out-Null
            git commit -m "feat(crest): v1.0 release - tools, vendor, shims, master SubModule.xml" 2>&1 | ForEach-Object { Write-Host "  $_" }
        }
    } else {
        Write-Host "  crest/ is not a git repo (skipping meta-commit)"
    }
} finally { Pop-Location }

# Step 4: package the bundle as CREST-v1.0.0.zip
Write-Host ""
Write-Host "==> Step 4: package CREST-v1.0.0.zip" -ForegroundColor Cyan
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force
$zipPath = New-CrestZip -Version '1.0.0'
if ($zipPath -and (Test-Path $zipPath)) {
    $size = (Get-Item $zipPath).Length / 1MB
    Write-Host ("  zip ready: {0}  ({1:N1} MB)" -f $zipPath, $size) -ForegroundColor Green
}

# Final summary
Write-Host ""
Write-Host "==== v1.0 SHIP SUMMARY ====" -ForegroundColor Green
foreach ($r in $repos) {
    Push-Location $r.Path
    try {
        $sha = (git rev-parse --short HEAD 2>$null).Trim()
        $msg = (git log -1 --pretty=%s 2>$null).Trim()
        $msgShort = if ($msg.Length -gt 70) { $msg.Substring(0,70) + "..." } else { $msg }
        Write-Host ("  {0,-25} {1}  {2}" -f $r.Name, $sha, $msgShort)
    } finally { Pop-Location }
}
if ($zipPath) {
    Write-Host ""
    Write-Host "  Distributable: $zipPath" -ForegroundColor Green
}
