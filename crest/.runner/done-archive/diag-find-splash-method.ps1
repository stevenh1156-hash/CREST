$ErrorActionPreference = 'Continue'
Add-Type -Path 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'

# Find TaleWorlds methods that play the startup splash video. Common candidates:
#   TaleWorlds.MountAndBlade.Module.PlayStartupVideos
#   TaleWorlds.MountAndBlade.Module.PlaySplashAnimation
#   TaleWorlds.MountAndBlade.View.SplashScreens.SplashScreenManager
$gameBin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\bin\Win64_Shipping_Client'
$nativeBin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\Native\bin\Win64_Shipping_Client'

$searchTerms = @('Splash','Intro','Startup','Logo','PlayVideo','Cinematic')

function Find-MethodsContaining {
    param([string]$Path, [string[]]$Patterns)
    if (-not (Test-Path $Path)) { return }
    $a = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($Path)
    try {
        foreach ($t in $a.MainModule.Types) {
            foreach ($pat in $Patterns) {
                if ($t.Name -match $pat -or $t.Namespace -match $pat) {
                    Write-Host ("  TYPE: {0}.{1}  in  {2}" -f $t.Namespace, $t.Name, (Split-Path $Path -Leaf)) -ForegroundColor Yellow
                    foreach ($m in $t.Methods) {
                        Write-Host ("       method: {0}" -f $m.Name)
                    }
                    break
                }
            }
            # Also check method names within type
            foreach ($m in $t.Methods) {
                foreach ($pat in $Patterns) {
                    if ($m.Name -match $pat) {
                        Write-Host ("  METHOD: {0}.{1}::{2}  in  {3}" -f $t.Namespace, $t.Name, $m.Name, (Split-Path $Path -Leaf))
                        break
                    }
                }
            }
        }
    } finally { $a.Dispose() }
}

Write-Host "==> Searching for splash/intro/startup video methods" -ForegroundColor Cyan
foreach ($dir in @($gameBin, $nativeBin)) {
    if (-not (Test-Path $dir)) { continue }
    $dlls = Get-ChildItem $dir -Filter 'TaleWorlds.*.dll' -ErrorAction SilentlyContinue
    foreach ($dll in $dlls) {
        Find-MethodsContaining -Path $dll.FullName -Patterns $searchTerms
    }
}
