$ErrorActionPreference = 'Continue'
Write-Host "==> Video files in Native module" -ForegroundColor Cyan
$nativeRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\Native'
foreach ($ext in 'ivf','wmv','mp4','avi','webm') {
    $files = Get-ChildItem -Recurse -File -Path $nativeRoot -Filter "*.$ext" -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        Write-Host ("  {0,9:N0}KB  {1}" -f ($f.Length/1KB), $f.FullName.Substring($nativeRoot.Length))
    }
}

# Also look game-root level
Write-Host ""
Write-Host "==> Video files in game root" -ForegroundColor Cyan
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
foreach ($ext in 'ivf','wmv','mp4','avi','webm') {
    $files = Get-ChildItem -Recurse -File -Path $gameRoot -Filter "*.$ext" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\Native\\' }
    foreach ($f in $files | Select-Object -First 20) {
        Write-Host ("  {0,9:N0}KB  {1}" -f ($f.Length/1KB), $f.FullName.Substring($gameRoot.Length))
    }
}
