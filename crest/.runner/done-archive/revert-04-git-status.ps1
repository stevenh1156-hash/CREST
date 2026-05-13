$ErrorActionPreference = 'Continue'

$repos = @(
    'C:\dev\bannerlord\Bannerlord.Harmony',
    'C:\dev\bannerlord\Bannerlord.ButterLib',
    'C:\dev\bannerlord\Bannerlord.UIExtenderEx',
    'C:\dev\bannerlord\Bannerlord.MBOptionScreen'
)

foreach ($r in $repos) {
    Write-Host ""
    Write-Host "==== $r ====" -ForegroundColor Cyan
    Push-Location $r
    try {
        Write-Host "  branch: $((git rev-parse --abbrev-ref HEAD).Trim())" -ForegroundColor DarkGray
        Write-Host "  HEAD: $((git log -1 --oneline).Trim())" -ForegroundColor DarkGray
        $shortStatus = git status --short 2>$null
        $count = ($shortStatus | Where-Object { $_ } | Measure-Object).Count
        Write-Host ("  uncommitted: $count files") -ForegroundColor $(if ($count -gt 0) { 'Yellow' } else { 'Green' })
        if ($count -gt 0 -and $count -le 10) {
            $shortStatus | ForEach-Object { Write-Host "    $_" }
        } elseif ($count -gt 10) {
            $shortStatus | Select-Object -First 8 | ForEach-Object { Write-Host "    $_" }
            Write-Host "    ... ($($count - 8) more)" -ForegroundColor DarkGray
        }
    } finally { Pop-Location }
}

Write-Host ""
Write-Host "==== If counts > 0, we can git checkout -- src/ src-ui/ tests/ to revert .cs file corruption ====" -ForegroundColor Cyan
Write-Host "==== then re-run revert-03 ONCE cleanly. ===="
