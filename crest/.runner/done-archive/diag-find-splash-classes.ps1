$ErrorActionPreference = 'Continue'
Add-Type -Path 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'

$gameBin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\bin\Win64_Shipping_Client'

# Look for video / movie / cinematic classes more broadly
$searchTerms = @(
    'MBSplash', 'SplashScreen', 'SplashState', 'MBInitialScreen',
    'MovieBox', 'VideoBrush', 'VideoPlayer', 'Cinematic',
    'IntroBackground', 'StartupBackground', 'MainMenu.*Background',
    'MainMenuView', 'MovieScreen', 'PlayMovie', 'PlayCinematic'
)

Write-Host "==> Searching all TaleWorlds DLLs for splash/movie types" -ForegroundColor Cyan
$dlls = Get-ChildItem $gameBin -Filter 'TaleWorlds.*.dll' -ErrorAction SilentlyContinue
foreach ($dll in $dlls) {
    try {
        $a = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dll.FullName)
        try {
            foreach ($t in $a.MainModule.Types) {
                $tname = "$($t.Namespace).$($t.Name)"
                foreach ($pat in $searchTerms) {
                    if ($tname -match $pat) {
                        Write-Host ("  TYPE: {0}  in  {1}" -f $tname, $dll.Name) -ForegroundColor Yellow
                        $methods = $t.Methods | Where-Object { -not $_.IsConstructor -or $_.Name -eq '.ctor' }
                        foreach ($m in $methods | Select-Object -First 8) {
                            $params = ($m.Parameters | ForEach-Object { $_.ParameterType.Name }) -join ', '
                            $vis = if ($m.IsPublic) { 'pub' } elseif ($m.IsAssembly) { 'int' } else { 'pri' }
                            Write-Host ("       [{0}] {1}({2})" -f $vis, $m.Name, $params)
                        }
                        break
                    }
                }
            }
        } finally { $a.Dispose() }
    } catch { }
}

# Also search for InitialMenu or InitialMain in Native module
Write-Host ""
Write-Host "==> Searching Modules\Native for InitialMenu types" -ForegroundColor Cyan
$nativeBin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\Native\bin\Win64_Shipping_Client'
if (Test-Path $nativeBin) {
    $dlls = Get-ChildItem $nativeBin -Filter '*.dll' -ErrorAction SilentlyContinue
    foreach ($dll in $dlls) {
        try {
            $a = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dll.FullName)
            try {
                foreach ($t in $a.MainModule.Types) {
                    $tname = "$($t.Namespace).$($t.Name)"
                    if ($tname -match 'InitialMenu|MainMenu|MovieView|IntroVideo|CinematicState|SplashState|InitialState') {
                        Write-Host ("  TYPE: {0}  in  {1}" -f $tname, $dll.Name) -ForegroundColor Yellow
                        $methods = $t.Methods | Select-Object -First 6
                        foreach ($m in $methods) {
                            Write-Host ("       {0}" -f $m.Name)
                        }
                    }
                }
            } finally { $a.Dispose() }
        } catch { }
    }
}

# Also check engine_config.txt for splash settings
Write-Host ""
Write-Host "==> engine_config.txt splash-related settings" -ForegroundColor Cyan
$cfg = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\engine_config.txt'
if (Test-Path $cfg) {
    Get-Content $cfg | Where-Object { $_ -match 'splash|video|intro|movie|logo|skip' -and $_ -notmatch '^#' } | Select-Object -First 20
}
