using System;

using HarmonyLib;
using HarmonyLib.BUTR.Extensions;

using TaleWorlds.MountAndBlade;

using Bannerlord.Harmony;  // CrestBetaBridge, CrestDiag

namespace Bannerlord.Harmony.Beta;

/// <summary>
/// Entry point for Crest.Harmony.Beta.dll.
///
/// Loaded via Assembly.LoadFrom + reflection from Crest.Harmony.dll
/// when Bannerlord's Native module reports v1.4.0 or higher. The main
/// DLL invokes <see cref="Initialize"/> with a fresh Harmony instance,
/// and BetaBootstrap wires every Beta-only feature into the running
/// process: registers Harmony patches, populates CrestBetaBridge
/// delegates that the main DLL invokes per-mission.
/// </summary>
public static class BetaBootstrap
{
    private const string Source = "BetaBootstrap";

    /// <summary>
    /// Called once from CrestBetaBridge.TryLoadAndInitialize on Beta
    /// installs. Sets up everything that depends on 1.4-only TaleWorlds
    /// API surface.
    /// </summary>
    public static void Initialize(HarmonyLib.Harmony harmony)
    {
        try
        {
            CrestDiag.Log(Source, "Initialize: registering Beta-only patches and bridge delegates");

            // 1. Register the cavalry-aware spawn limiter Harmony patches.
            //    These bind DefaultBattleMissionAgentSpawnLogic methods
            //    that don't exist on e1.3.x.
            CrestBattleSizeBetaPatches.Register(harmony);

            // 2. Wire the convergence-mission-behavior delegate. Main DLL's
            //    CrestBattleConvergence.AddMissionBehaviors invokes this
            //    per mission to add the CrestBattleConvergenceLogic
            //    behavior. The default (delegate null) on Public installs
            //    means convergence silently no-ops there.
            CrestBetaBridge.AddConvergenceMissionBehavior = AddConvergenceBehavior;

            // 3. The main DLL's CrestBattleSize.TryApply invokes
            //    CrestBetaBridge.RegisterBetaPatches which we wire to
            //    Register above. But TryApply already ran (it's called
            //    from a different lifecycle hook), so we run the spawn
            //    limiter registration directly above. Set the delegate
            //    too so any future TryApply re-invocation also lights up.
            CrestBetaBridge.RegisterBetaPatches = CrestBattleSizeBetaPatches.Register;

            CrestDiag.Log(Source, "Initialize: complete");
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "Initialize", ex);
        }
    }

    /// <summary>
    /// Per-mission factory used by the main DLL's CrestBattleConvergence.
    /// Wrapped in a method (instead of a lambda) so reflection can find
    /// it for diagnostic logging if needed.
    /// </summary>
    private static void AddConvergenceBehavior(Mission mission)
    {
        try
        {
            mission.AddMissionBehavior(new CrestBattleConvergenceLogic());
            CrestDiag.Log(Source, "added CrestBattleConvergenceLogic to mission");
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "AddConvergenceBehavior", ex);
        }
    }
}
