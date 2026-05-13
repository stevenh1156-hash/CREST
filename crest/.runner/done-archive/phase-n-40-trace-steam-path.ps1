$ErrorActionPreference = 'Continue'

# Add a marker write to ALL three launcher paths so when the user launches via
# Steam or BLSE.Launcher we'll see which path the process took.
# TaleWorlds.MountAndBlade.Launcher.exe is a binary we can't modify -- but
# the .exe.config redirects to BLSEAppDomainManager which does run our code.
# Bannerlord.BLSE.Launcher.exe and BLSE.LauncherEx.exe are our binaries.

# Check: did the user reconfigure Steam to launch BLSE.LauncherEx? Read the
# Steam launch options for Bannerlord (appid 261550)
Write-Host '==> Inspecting Steam launch options' -ForegroundColor Cyan
$steamPath = ${env:ProgramFiles(x86)} + '\Steam'
$libCfg = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
if (Test-Path $libCfg) {
    Write-Host ('   libraryfolders.vdf at ' + $libCfg)
}

# Look at localconfig.vdf for the app's LaunchOptions
$users = Get-ChildItem (Join-Path $steamPath 'userdata') -Directory -ErrorAction SilentlyContinue
foreach ($u in $users) {
    $localCfg = Join-Path $u.FullName 'config\localconfig.vdf'
    if (Test-Path $localCfg) {
        Write-Host ("   user " + $u.Name + ": localconfig.vdf present")
        # Search for "261550" block
        $content = Get-Content $localCfg -Raw
        $idx = $content.IndexOf('"261550"')
        if ($idx -ge 0) {
            $end = [Math]::Min($idx + 1000, $content.Length - 1)
            $block = $content.Substring($idx, $end - $idx)
            Write-Host '   Bannerlord (261550) block excerpt:'
            $block -split "`n" | Where-Object { $_ -match 'Launch|261550' } | Select-Object -First 5 | ForEach-Object {
                Write-Host ('     ' + $_)
            }
        } else {
            Write-Host '   no 261550 block in this user'
        }
    }
}

Write-Host ''
Write-Host '==> Bannerlord.BLSE.Launcher.exe entry point' -ForegroundColor Cyan
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$cecilDll = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client\Mono.Cecil.dll'
$blseLauncher = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.BLSE.Launcher.exe'
[Reflection.Assembly]::LoadFrom($cecilDll) | Out-Null
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($blseLauncher)
Write-Host '   types in BLSE.Launcher.exe:'
$asm.MainModule.Types | Where-Object { $_.Name -ne '<Module>' -and $_.FullName -notmatch '^System\.|^Microsoft\.|^Windows\.' } |
    ForEach-Object { Write-Host ('     ' + $_.FullName) }

# Check if it has Program.Main with #if LAUNCHER instead of LAUNCHEREX
$prog = $asm.MainModule.Types | Where-Object { $_.Name -eq 'Program' -and $_.Namespace -eq 'Bannerlord.BLSE' }
if ($prog) {
    $main = $prog.Methods | Where-Object { $_.Name -eq 'Main' }
    Write-Host '   Main IL strings (looking for "launcher" vs "launcherex"):'
    $main.Body.Instructions | Where-Object { $_.Operand -is [string] } | Select-Object -First 5 | ForEach-Object {
        Write-Host ('     "' + $_.Operand + '"')
    }
}
$asm.Dispose()
