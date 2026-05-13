using HarmonyLib;
using HarmonyLib.BUTR.Extensions;

using System;
using System.Reflection;

using TaleWorlds.MountAndBlade;

namespace Bannerlord.Harmony;

/// <summary>
/// CREST QuickStart -- Phase J: Skip the TaleWorlds + Partners intro video that plays
/// after launcher splash but before the main menu.
///
/// Flow that we're patching:
///   1. TaleWorlds.MountAndBlade.Module.SetInitialModuleScreenAsRootScreen() creates a
///      VideoPlaybackState (a GameState) with hardcoded path "Videos/TWLogo_and_Partners.ivf"
///      and pushes it onto the GameStateManager. The state has an _onVideoFinised callback
///      (sic -- typo in upstream) that advances to MBInitialState (the main menu) once the
///      video finishes.
///   2. The engine activates VideoPlaybackState; it calls VideoPlaybackState.OnVideoStarted()
///      when the engine reports the native player is ready.
///   3. When the video reaches the end, VideoPlaybackState.OnVideoFinished() is called,
///      which invokes the _onVideoFinised callback to push MBInitialState.
///
/// Our patch: postfix VideoPlaybackState.OnVideoStarted to immediately call OnVideoFinished
/// on the same instance. The engine never plays the video; the state machine advances
/// straight to the main menu.
///
/// Activated unconditionally for v1.0 (no MCM toggle yet -- that's Phase L). To disable,
/// set environment variable CREST_SKIP_INTRO=0 before launching.
/// </summary>
internal static class CrestQuickStart
{
    private static bool _enabled = true;
    private static bool _patched;

    public static void Apply(HarmonyLib.Harmony harmony)
    {
        if (_patched) return;
        _patched = true;

        if (Environment.GetEnvironmentVariable("CREST_SKIP_INTRO") == "0"
            || !CrestConfig.IsEnabled("SkipIntroVideo"))
        {
            _enabled = false;
            return;
        }

        try
        {
            // VideoPlaybackState is the GameState pushed for any startup video playback
            // (currently only TWLogo_and_Partners.ivf in 1.4.x). Patching its
            // OnVideoStarted to immediately fire OnVideoFinished cleanly advances the
            // state machine without playing the video.
            var stateType = AccessTools2.TypeByName("TaleWorlds.MountAndBlade.VideoPlaybackState");
            if (stateType == null)
            {
                CrestDiag.LogTypeNotFound(nameof(CrestQuickStart), "TaleWorlds.MountAndBlade.VideoPlaybackState");
                return;
            }

            var onVideoStarted = AccessTools2.Method(stateType, "OnVideoStarted", Type.EmptyTypes);
            if (onVideoStarted == null)
            {
                CrestDiag.Log(nameof(CrestQuickStart), "VideoPlaybackState.OnVideoStarted not found");
                return;
            }

            harmony.Patch(onVideoStarted,
                postfix: new HarmonyMethod(typeof(CrestQuickStart), nameof(OnVideoStarted_Postfix)));
            CrestDiag.Log(nameof(CrestQuickStart), "patched VideoPlaybackState.OnVideoStarted");
        }
        catch (Exception ex)
        {
            // Never break startup over an optional cosmetic patch -- but log so we know.
            CrestDiag.LogCaught(nameof(CrestQuickStart), "Apply", ex);
        }
    }

    private static void OnVideoStarted_Postfix(object __instance)
    {
        if (!_enabled) return;
        try
        {
            // Immediately fire OnVideoFinished to advance to the main-menu state.
            var onVideoFinished = __instance.GetType().GetMethod("OnVideoFinished",
                BindingFlags.Public | BindingFlags.Instance);
            // Pass Array.Empty<object>() rather than null to be defensive against
            // .NET reflection paths that don't accept null for an empty argument list.
            onVideoFinished?.Invoke(__instance, Array.Empty<object>());
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(nameof(CrestQuickStart), "OnVideoStarted_Postfix", ex);
        }
    }
}
