using System;
using System.IO;
using System.Reflection;

using HarmonyLib;

using TaleWorlds.MountAndBlade;

namespace Bannerlord.Harmony;

/// <summary>
/// Cross-assembly bridge between the always-loaded Crest.Harmony.dll
/// (Public build, runs on both e1.3.x and e1.4.x) and the optional
/// Crest.Harmony.Beta.dll (loaded only on e1.4.x+ to provide features
/// that depend on 1.4-only TaleWorlds API surface).
///
/// On a Public install (Bannerlord e1.3.x), the Beta DLL is never
/// loaded; every delegate field below stays null and the corresponding
/// feature is silently absent. On a Beta install, SubModule.OnSubModuleLoad
/// probes the running game version, calls Assembly.LoadFrom on
/// Crest.Harmony.Beta.dll, and invokes its BetaBootstrap.Initialize
/// entry point. BetaBootstrap then assigns the delegates here, which
/// the main DLL invokes from CrestBattleConvergence.AddMissionBehaviors,
/// CrestBattleSize.TryApply, etc.
///
/// Why a bridge instead of an interface or virtual call: keeps the
/// main DLL's compile-time dependency graph completely free of any
/// 1.4-only TaleWorlds types. The delegates traffic in already-loaded
/// types (Mission, HarmonyLib.Harmony) that exist on both branches.
/// </summary>
public static class CrestBetaBridge
{
    /// <summary>
    /// Set by BetaBootstrap.Initialize when the Beta DLL loads. Adds
    /// any Beta-only Harmony patches (the cavalry-aware spawn limiter
    /// in CrestBattleSize, etc.) to the supplied harmony instance.
    /// </summary>
    public static Action<HarmonyLib.Harmony>? RegisterBetaPatches;

    /// <summary>
    /// Set by BetaBootstrap.Initialize. Adds the
    /// CrestBattleConvergenceLogic MissionBehavior to the given mission.
    /// Called from CrestBattleConvergence.AddMissionBehaviors on each
    /// new mission.
    /// </summary>
    public static Action<Mission>? AddConvergenceMissionBehavior;

    /// <summary>
    /// True once Initialize has been called and the delegates are wired.
    /// Read-only state for diagnostic logging.
    /// </summary>
    public static bool IsLoaded { get; private set; }

    /// <summary>
    /// Probe the running game's Native module version. Returns true on
    /// e1.4.0 or newer, false on e1.3.x and below. Used by SubModule
    /// to decide whether to load Crest.Harmony.Beta.dll.
    /// </summary>
    public static bool ShouldLoadBeta()
    {
        try
        {
            var version = ProbeNativeModuleVersion();
            if (string.IsNullOrEmpty(version)) return false;

            // Strip leading "v" / "e" (BUTR convention)
            var v = version.TrimStart('v', 'V', 'e', 'E');
            var parts = v.Split('.');
            if (parts.Length < 2) return false;
            if (!int.TryParse(parts[0], out var major)) return false;
            if (!int.TryParse(parts[1], out var minor)) return false;

            // Anything 1.4.x or higher: load Beta. e1.3.x: skip.
            if (major > 1) return true;
            if (major == 1 && minor >= 4) return true;
            return false;
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught("CrestBetaBridge", "ShouldLoadBeta", ex);
            return false;
        }
    }

    /// <summary>
    /// Try to load Crest.Harmony.Beta.dll from the same directory as
    /// this assembly, find its BetaBootstrap.Initialize method, and
    /// invoke it with the supplied harmony instance. Returns true on
    /// success.
    /// </summary>
    public static bool TryLoadAndInitialize(HarmonyLib.Harmony harmony)
    {
        try
        {
            var thisDir = Path.GetDirectoryName(typeof(CrestBetaBridge).Assembly.Location);
            if (string.IsNullOrEmpty(thisDir))
            {
                CrestDiag.Log("CrestBetaBridge", "TryLoadAndInitialize: assembly location is empty");
                return false;
            }

            var betaPath = Path.Combine(thisDir, "Crest.Harmony.Beta.dll");
            if (!File.Exists(betaPath))
            {
                CrestDiag.Log("CrestBetaBridge", "TryLoadAndInitialize: Crest.Harmony.Beta.dll not found at " + betaPath);
                return false;
            }

            var asm = Assembly.LoadFrom(betaPath);
            var bootstrapType = asm.GetType("Bannerlord.Harmony.Beta.BetaBootstrap");
            if (bootstrapType == null)
            {
                CrestDiag.Log("CrestBetaBridge", "TryLoadAndInitialize: BetaBootstrap type missing from Beta assembly");
                return false;
            }

            var initMethod = bootstrapType.GetMethod("Initialize",
                BindingFlags.Public | BindingFlags.Static);
            if (initMethod == null)
            {
                CrestDiag.Log("CrestBetaBridge", "TryLoadAndInitialize: BetaBootstrap.Initialize method missing");
                return false;
            }

            initMethod.Invoke(null, new object[] { harmony });
            IsLoaded = true;
            CrestDiag.Log("CrestBetaBridge", "Beta DLL loaded; convergence + spawn limiter active");
            return true;
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught("CrestBetaBridge", "TryLoadAndInitialize", ex);
            return false;
        }
    }

    /// <summary>
    /// Walk module subfolders to find Modules\Native\SubModule.xml and
    /// extract its Version value. Falls back to assembly metadata if
    /// the file isn't reachable.
    /// </summary>
    private static string ProbeNativeModuleVersion()
    {
        try
        {
            // Walk up from this assembly's location: Modules\CREST\bin\Win64_Shipping_Client\Crest.Harmony.dll
            // → ../../../Native/SubModule.xml
            var asmLoc = typeof(CrestBetaBridge).Assembly.Location;
            if (string.IsNullOrEmpty(asmLoc)) return "";
            var binDir = Path.GetDirectoryName(asmLoc);                              // ...\bin\Win64_Shipping_Client
            if (binDir == null) return "";
            var binParent = Directory.GetParent(binDir);                             // ...\bin
            if (binParent == null) return "";
            var crestRoot = binParent.Parent;                                        // ...\CREST
            if (crestRoot == null) return "";
            var modulesRoot = crestRoot.Parent;                                      // ...\Modules
            if (modulesRoot == null) return "";

            var nativeXml = Path.Combine(modulesRoot.FullName, "Native", "SubModule.xml");
            if (!File.Exists(nativeXml)) return "";

            var contents = File.ReadAllText(nativeXml);
            // Find <Version value="vX.Y.Z" />
            var marker = "<Version value";
            var i = contents.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
            if (i < 0) return "";
            var quote1 = contents.IndexOf('"', i);
            if (quote1 < 0) return "";
            var quote2 = contents.IndexOf('"', quote1 + 1);
            if (quote2 < 0) return "";
            return contents.Substring(quote1 + 1, quote2 - quote1 - 1);
        }
        catch
        {
            return "";
        }
    }
}
