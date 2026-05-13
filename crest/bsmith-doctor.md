
Crest-Doctor
Game root: C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord
Docs root: C:\Users\Steve\OneDrive\Documents\Mount and Blade II Bannerlord
Generated: 2026-05-06 05:28:02

# Health check
========================================================================

## CREST module
  [OK]    Crest.Harmony.dll
  [OK]    Crest.ButterLib.dll
  [OK]    Crest.ButterLib.Implementation.dll
  [OK]    Crest.UIExtenderEx.dll
  [OK]    Crest.MCM.dll
  [OK]    CREST.v1.4.1.dll
  [OK]    Bannerlord.Harmony.dll
  [OK]    Bannerlord.ButterLib.dll
  [OK]    Bannerlord.UIExtenderEx.dll
  [OK]    MCMv5.dll
  [OK]    0Harmony.dll
  [OK]    Mono.Cecil.dll
  [INFO]  all 12 core DLLs present

## BLSE injection
  [OK]    Bannerlord.BLSE.dll deployed in game bin
  [OK]    Launcher .config has AppDomainManager redirect
  [OK]    Bannerlord.exe.config present (covers direct-game launch path)

## Stub modules
  [OK]    Bannerlord.Harmony stub: 2364B; DefaultModule=true; not yet in LauncherData (will appear after first launch)
  [OK]    Bannerlord.ButterLib stub: 945B; DefaultModule=true; not yet in LauncherData (will appear after first launch)
  [OK]    Bannerlord.UIExtenderEx stub: 1023B; DefaultModule=true; not yet in LauncherData (will appear after first launch)
  [OK]    Bannerlord.MBOptionScreen stub: 1036B; DefaultModule=true; not yet in LauncherData (will appear after first launch)

## crest.json
  [OK]    crest.json present + parses
  [INFO]    AutoUnblock = true
  [INFO]    ButterLib = true
  [INFO]    MainMenuMonotone = true
  [INFO]    MCM = true
  [INFO]    MCMBasicImplementation = true
  [INFO]    MCMUI = true
  [INFO]    RuntimeSelfTest = false
  [INFO]    RuntimeSelfTestVerbose = false
  [INFO]    SkipIntroVideo = true
  [INFO]    SuppressMainMenuMessages = true

## Game version sanity
  [INFO]  TaleWorlds.MountAndBlade.dll v1.0.0.0
  [INFO]  CREST built for game v1.4.1

# Load-order analysis
========================================================================
  [INFO]  found 46 modules with valid SubModule.xml

## Missing dependencies
  [ERR]   FasterTime depends on WarSails -- not installed

## Dependency cycles
  [OK]    no dependency cycles

## Launcher load-order vs declared dependencies
  [OK]    every dep loads before its consumer in LauncherData

# Compatibility risks
========================================================================

## Bundled-Harmony collisions
  [OK]    no other module bundles 0Harmony / Mono.Cecil / MonoMod

## TaleWorlds DLL overrides
  [INFO]  community modules shipping TaleWorlds.*.dll (engine override pattern):
  [WARN]  RBM ships TaleWorlds.MountAndBlade.CustomBattle.dll (differs from all canonical copies -- mod likely depends on it)
  [WARN]  RBM ships TaleWorlds.MountAndBlade.Multiplayer.dll (differs from all canonical copies -- mod likely depends on it)
  [INFO]    Run Crest-Compat -Fix to auto-remove identical-content overrides; differing ones require manual review.

# Logs aggregator
========================================================================
  [INFO]  reading default20260506.log
  [INFO]  reading runtime.log

## Errors and warnings (most recent first)
  2026-05-06T04:57:01.7390699-05:00 [ERR]    [System.Diagnostics.Logger.LoggerTraceListener] 
  2026-05-06T04:57:01.6344339-05:00 [ERR]    [System.Diagnostics.Logger.LoggerTraceListener] AccessTools2.DeclaredMethod: Could not find method for type 'TaleWorlds.GauntletUI.WidgetInfo' and name ...
  2026-05-06T04:57:01.6329315-05:00 [ERR]    [System.Diagnostics.Logger.LoggerTraceListener] AccessTools2.Method: Could not find method for type 'TaleWorlds.MountAndBlade.Module' and name 'Finalize...
  2026-05-06T04:56:55.3387131-05:00 [ERR]    [Bannerlord.ButterLib.Implementation.MBSubModuleBaseExtended.Patches.ModulePatch] miTargetMethodUnLoad is null!
  2026-05-06T04:48:24.5720049-05:00 [ERR]    [System.Diagnostics.Logger.LoggerTraceListener] 
  2026-05-06T04:48:24.4804267-05:00 [ERR]    [System.Diagnostics.Logger.LoggerTraceListener] AccessTools2.DeclaredMethod: Could not find method for type 'TaleWorlds.GauntletUI.WidgetInfo' and name ...
  2026-05-06T04:48:24.4779244-05:00 [ERR]    [System.Diagnostics.Logger.LoggerTraceListener] AccessTools2.Method: Could not find method for type 'TaleWorlds.MountAndBlade.Module' and name 'Finalize...
  2026-05-06T04:48:18.1629433-05:00 [ERR]    [Bannerlord.ButterLib.Implementation.MBSubModuleBaseExtended.Patches.ModulePatch] miTargetMethodUnLoad is null!
  2026-05-06T03:16:48.3190991-05:00 [ERR]    [System.Diagnostics.Logger.LoggerTraceListener] 
  2026-05-06T03:16:48.2285063-05:00 [ERR]    [System.Diagnostics.Logger.LoggerTraceListener] AccessTools2.DeclaredMethod: Could not find method for type 'TaleWorlds.GauntletUI.WidgetInfo' and name ...
  2026-05-06T03:16:48.2260055-05:00 [ERR]    [System.Diagnostics.Logger.LoggerTraceListener] AccessTools2.Method: Could not find method for type 'TaleWorlds.MountAndBlade.Module' and name 'Finalize...
  2026-05-06T03:16:41.9203576-05:00 [ERR]    [Bannerlord.ButterLib.Implementation.MBSubModuleBaseExtended.Patches.ModulePatch] miTargetMethodUnLoad is null!
  2026-05-06T03:08:06.1337043-05:00 [ERR]    [System.Diagnostics.Logger.LoggerTraceListener] 
  2026-05-06T03:08:06.0346030-05:00 [ERR]    [System.Diagnostics.Logger.LoggerTraceListener] AccessTools2.DeclaredMethod: Could not find method for type 'TaleWorlds.GauntletUI.WidgetInfo' and name ...
  2026-05-06T03:08:06.0326031-05:00 [ERR]    [System.Diagnostics.Logger.LoggerTraceListener] AccessTools2.Method: Could not find method for type 'TaleWorlds.MountAndBlade.Module' and name 'Finalize...
  2026-05-06T03:07:59.6454252-05:00 [ERR]    [Bannerlord.ButterLib.Implementation.MBSubModuleBaseExtended.Patches.ModulePatch] miTargetMethodUnLoad is null!
  2026-05-06T03:02:45.6995500-05:00 [ERR]    [System.Diagnostics.Logger.LoggerTraceListener] 
  2026-05-06T03:02:45.6034444-05:00 [ERR]    [System.Diagnostics.Logger.LoggerTraceListener] AccessTools2.DeclaredMethod: Could not find method for type 'TaleWorlds.GauntletUI.WidgetInfo' and name ...
  2026-05-06T03:02:45.6009445-05:00 [ERR]    [System.Diagnostics.Logger.LoggerTraceListener] AccessTools2.Method: Could not find method for type 'TaleWorlds.MountAndBlade.Module' and name 'Finalize...
  2026-05-06T03:02:39.3259254-05:00 [ERR]    [Bannerlord.ButterLib.Implementation.MBSubModuleBaseExtended.Patches.ModulePatch] miTargetMethodUnLoad is null!
  2026-05-06T02:24:31.8433079-05:00 [WRN]    [Bannerlord.FluidCombatNext.SubModule] FluidCombatNext: Don't forget to unbind default attack and block if using Fluid Attack or Fluid Block!
  2026-05-06T02:24:30.9773958-05:00 [ERR]    [System.Diagnostics.Logger.LoggerTraceListener] 
  2026-05-06T02:24:30.8872924-05:00 [ERR]    [System.Diagnostics.Logger.LoggerTraceListener] AccessTools2.DeclaredMethod: Could not find method for type 'TaleWorlds.GauntletUI.WidgetInfo' and name ...
  2026-05-06T02:24:30.8847925-05:00 [ERR]    [System.Diagnostics.Logger.LoggerTraceListener] AccessTools2.Method: Could not find method for type 'TaleWorlds.MountAndBlade.Module' and name 'Finalize...
  2026-05-06T02:24:24.3304426-05:00 [ERR]    [Bannerlord.ButterLib.Implementation.MBSubModuleBaseExtended.Patches.ModulePatch] miTargetMethodUnLoad is null!
  2026-05-06T02:23:53.4885700-05:00 [ERR]    [System.Diagnostics.Logger.LoggerTraceListener] 
  2026-05-06T02:23:53.3979779-05:00 [ERR]    [System.Diagnostics.Logger.LoggerTraceListener] AccessTools2.DeclaredMethod: Could not find method for type 'TaleWorlds.GauntletUI.WidgetInfo' and name ...
  2026-05-06T02:23:53.3954734-05:00 [ERR]    [System.Diagnostics.Logger.LoggerTraceListener] AccessTools2.Method: Could not find method for type 'TaleWorlds.MountAndBlade.Module' and name 'Finalize...
  2026-05-06T02:23:47.1559063-05:00 [ERR]    [Bannerlord.ButterLib.Implementation.MBSubModuleBaseExtended.Patches.ModulePatch] miTargetMethodUnLoad is null!
  2026-05-06T02:19:37.3352477-05:00 [ERR]    [Bannerlord.ButterLib.Implementation.MBSubModuleBaseExtended.Patches.ModulePatch] miTargetMethodUnLoad is null!

## Errors grouped by source
  [INFO]      33 ERR  System.Diagnostics.Logger.LoggerTraceListener
  [INFO]      14 ERR  Bannerlord.ButterLib.Implementation.MBSubModuleBaseExtended.Patches.ModulePatch
