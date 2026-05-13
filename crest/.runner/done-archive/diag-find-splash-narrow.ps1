$ErrorActionPreference = 'Continue'
Add-Type -Path 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'

$gameBin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\bin\Win64_Shipping_Client'

# Look for the InitialModuleScreen (which precedes the main menu) and any
# splash/intro classes
$searchTerms = @(
    'InitialState', 'InitialMovie', 'InitialAnimation', 'SplashAnimation',
    'IntroVideo', 'IntroLogo', 'StartupSplash', 'SplashState', 'InitialState',
    'TaleWorlds.MountAndBlade.SplashScreen', 'PlayMovie', 'StartScreen'
)

Write-Host "==> Narrow search for splash/intro related types and methods" -ForegroundColor Cyan
$dlls = Get-ChildItem $gameBin -Filter 'TaleWorlds.MountAndBlade*.dll' -ErrorAction SilentlyContinue
foreach ($dll in $dlls) {
    $a = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dll.FullName)
    try {
        foreach ($t in $a.MainModule.Types) {
            $tname = "$($t.Namespace).$($t.Name)"
            foreach ($pat in $searchTerms) {
                if ($tname -match $pat) {
                    Write-Host ("  TYPE: {0}  ({1})" -f $tname, $dll.Name) -ForegroundColor Yellow
                    foreach ($m in $t.Methods) {
                        if ($m.IsStatic -or $m.IsPublic) {
                            $params = ($m.Parameters | ForEach-Object { $_.ParameterType.Name }) -join ', '
                            Write-Host ("       {0}({1})" -f $m.Name, $params)
                        }
                    }
                }
            }
        }
    } finally { $a.Dispose() }
}

# Also look for the SetInitialModuleScreenAsRootScreen method signature
Write-Host ""
Write-Host "==> Methods named 'SetInitialModuleScreenAsRootScreen' or 'StartingState':" -ForegroundColor Cyan
foreach ($dll in $dlls) {
    $a = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dll.FullName)
    try {
        foreach ($t in $a.MainModule.Types) {
            foreach ($m in $t.Methods) {
                if ($m.Name -match 'InitialModuleScreen|InitialState|StartingState|InitMenu') {
                    Write-Host ("  {0}.{1}::{2}" -f $t.Namespace, $t.Name, $m.Name)
                }
            }
        }
    } finally { $a.Dispose() }
}

# Look at the Module class in TaleWorlds.MountAndBlade to find startup methods
Write-Host ""
Write-Host "==> All static/public methods on TaleWorlds.MountAndBlade.Module:" -ForegroundColor Cyan
$mb = Join-Path $gameBin 'TaleWorlds.MountAndBlade.dll'
$a = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($mb)
try {
    $modType = $a.MainModule.Types | Where-Object { $_.FullName -eq 'TaleWorlds.MountAndBlade.Module' }
    if ($modType) {
        foreach ($m in $modType.Methods) {
            $params = ($m.Parameters | ForEach-Object { $_.ParameterType.Name }) -join ', '
            $vis = if ($m.IsPublic) { 'pub' } elseif ($m.IsAssembly) { 'int' } else { 'pri' }
            $stat = if ($m.IsStatic) { 'static' } else { 'inst' }
            Write-Host ("       [{0}/{1}] {2}({3})" -f $vis, $stat, $m.Name, $params)
        }
    } else {
        Write-Host "    Module class not found" -ForegroundColor Red
    }
} finally { $a.Dispose() }
