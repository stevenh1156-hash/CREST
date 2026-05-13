$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

# Revert cross-fork using statements in MCM source.
# MCM UI references Crest.ButterLib and Crest.UIExtenderEx (sibling forks).
# Those didn't get touched by reset-02's MCM-only pattern.

Write-Host "==> Reverting cross-fork using statements in MCM source" -ForegroundColor Cyan

$mcmRoot = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen'
$From = @('Crest.ButterLib', 'Crest.UIExtenderEx', 'Crest.Harmony')
$To   = @('Bannerlord.ButterLib', 'Bannerlord.UIExtenderEx', 'Bannerlord.Harmony')

$files = @()
foreach ($subdir in @('src','src-ui','tests')) {
    $path = Join-Path $mcmRoot $subdir
    if (Test-Path $path) {
        $files += Get-ChildItem -Recurse -File -Path $path -Include '*.cs' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notlike '*\bin\*' -and $_.FullName -notlike '*\obj\*' }
    }
}
Write-Host "  scanning $($files.Count) MCM .cs files"

$changed = 0
$totalReplacements = 0
foreach ($f in $files) {
    $content = [System.IO.File]::ReadAllText($f.FullName)
    $orig = $content
    $fileChanges = 0
    for ($i = 0; $i -lt $From.Count; $i++) {
        $find = $From[$i]
        $replace = $To[$i]
        $count = ([regex]::Matches($content, [regex]::Escape($find))).Count
        if ($count -gt 0) {
            $fileChanges += $count
            $content = $content.Replace($find, $replace)
        }
    }
    if ($fileChanges -gt 0) {
        $totalReplacements += $fileChanges
        try {
            [System.IO.File]::WriteAllText($f.FullName, $content, [System.Text.UTF8Encoding]::new($false))
            $changed++
        } catch {
            Write-Host ("  ! write failed: $($f.FullName)") -ForegroundColor Red
        }
    }
}
Write-Host "  rewrote $changed files / $totalReplacements replacements"

# Verify
$residual = 0
foreach ($f in $files) {
    $c = [System.IO.File]::ReadAllText($f.FullName)
    foreach ($p in $From) {
        if ($c -match [regex]::Escape($p)) { $residual++; break }
    }
}
Write-Host ("  files still containing any of $($From -join ', '): $residual")

# Also check ProjectReference paths in csprojs - they reference Crest.X csprojs which is fine
# (those still exist as filenames). No need to update those.

Write-Host ""
Write-Host "==> Retry MCM build" -ForegroundColor Cyan
$ok = Build-CrestRepo -Name 'MCM'
if (-not $ok) { Write-Error "MCM build failed"; exit 1 }

Write-Host ""
Write-Host "==> Now run flip-internals + shim generator" -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\shims\flip-internals-public.ps1'
& 'C:\dev\bannerlord\crest\shims\generate-shims.ps1'

Write-Host ""
Write-Host "==> Final shim outputs:" -ForegroundColor Cyan
Add-Type -Path 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'
$shims = @(
    'C:\dev\bannerlord\crest\shims\Bannerlord.Harmony.Shim\Bannerlord.Harmony.dll',
    'C:\dev\bannerlord\crest\shims\Bannerlord.ButterLib.Shim\Bannerlord.ButterLib.dll',
    'C:\dev\bannerlord\crest\shims\Bannerlord.UIExtenderEx.Shim\Bannerlord.UIExtenderEx.dll',
    'C:\dev\bannerlord\crest\shims\MCMv5.Shim\MCMv5.dll'
)
foreach ($s in $shims) {
    if (Test-Path $s) {
        $a = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($s)
        try {
            Write-Host ("  {0,9:N0}B  {1}  ({2} forwarders)" -f (Get-Item $s).Length, (Split-Path $s -Leaf), $a.MainModule.ExportedTypes.Count) -ForegroundColor Green
            $a.MainModule.ExportedTypes | Select-Object -First 3 | ForEach-Object {
                Write-Host ("    {0}.{1}  ->  {2}" -f $_.Namespace, $_.Name, $_.Scope.Name)
            }
        } finally { $a.Dispose() }
    }
}
