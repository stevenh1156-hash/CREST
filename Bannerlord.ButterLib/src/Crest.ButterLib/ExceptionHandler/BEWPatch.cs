using Bannerlord.ButterLib.ExceptionHandler.DebuggerDetection;

using HarmonyLib;
using HarmonyLib.BUTR.Extensions;

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Bannerlord.ButterLib.ExceptionHandler;

// BEW commentary:
// TaleWorlds.DotNet.Managed:ApplicationTick                              -> Replicated
// TaleWorlds.Engine.ScriptComponentBehaviour:OnTick                      -> Called by TaleWorlds.Engine.ManagedScriptHolder:TickComponents
// TaleWorlds.MountAndBlade.Module:OnApplicationTick                      -> Replicated
// TaleWorlds.MountAndBlade.View.Missions.MissionView:OnMissionScreenTick -> Called by TaleWorlds.MountAndBlade.View.Screen.MissionScreen:OnFrameTick
// TaleWorlds.ScreenSystem.ScreenManager:Tick                             -> Replicated
// TaleWorlds.MountAndBlade.Mission:Tick                                  -> Replicated
// TaleWorlds.MountAndBlade.MissionBehaviour:OnMissionTick                -> Called by TaleWorlds.MountAndBlade.Mission:Tick
// TaleWorlds.MountAndBlade.MBSubModuleBase:OnSubModuleLoad               -> Replicated
internal sealed class BEWPatch
{
    private static bool _cachedDebuggerAttached;
    private static int _lastCheckTicks;

    public static bool IsDebuggerAttached()
    {
        var currentTicks = Environment.TickCount;
        if (currentTicks - _lastCheckTicks < 100)
            return _cachedDebuggerAttached;

        _cachedDebuggerAttached = false;

        if (Debugger.IsAttached)
            _cachedDebuggerAttached = true;

        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            _cachedDebuggerAttached = ProcessDebug.CheckProcessDebugObjectHandle();

        _lastCheckTicks = currentTicks;
        return _cachedDebuggerAttached;
    }

    private static readonly string[] BEW = ["org.calradia.admiralnelson.betterexceptionwindow"];


    private static readonly MethodInfo? ManagedApplicationTickMethod = AccessTools2.Method("TaleWorlds.DotNet.Managed:ApplicationTick");
    private static readonly MethodInfo? ModuleOnApplicationTickMethod = AccessTools2.Method("TaleWorlds.MountAndBlade.Module:OnApplicationTick");
    private static readonly MethodInfo? ScreenManagerTickMethod = AccessTools2.Method("TaleWorlds.ScreenSystem.ScreenManager:Tick");
    private static readonly MethodInfo? ManagedScriptHolderTickComponentsMethod = AccessTools2.Method("TaleWorlds.Engine.ManagedScriptHolder:TickComponents");
    private static readonly MethodInfo? MissionTickMethod = AccessTools2.Method("TaleWorlds.MountAndBlade.Mission:Tick");
    public static readonly MethodInfo? FinalizerMethod = SymbolExtensions2.GetMethodInfo((Exception x) => Finalizer(x));

    private static void Finalizer(Exception? __exception)
    {
        if (__exception is null)
            return;

        if (ExceptionHandlerSubSystem.Instance?.DisableWhenDebuggerIsAttached == true && IsDebuggerAttached())
            return;

        ExceptionReporter.Show(__exception);
    }

    // Mirror diagnostic lines into Modules\CREST\runtime.log via reflection
    // into Crest.Harmony.CrestDiag (loaded earlier in the SubModule chain).
    // Same compile-time-independent pattern used by ExceptionReporter.cs.
    private static void DiagLog(string source, string message)
    {
        try
        {
            var crestDiagType = Type.GetType("Bannerlord.Harmony.CrestDiag, Crest.Harmony");
            var logMethod = crestDiagType?.GetMethod("Log",
                BindingFlags.Public | BindingFlags.Static,
                null,
                new[] { typeof(string), typeof(string) },
                null);
            logMethod?.Invoke(null, new object[] { source, message });
        }
        catch
        {
            // never let mirror-logging failure block the bind.
        }
    }

    private static void TryPatchOne(Harmony harmony, MethodInfo? target, string label)
    {
        if (target == null)
        {
            DiagLog("BEWPatch", label + " skipped: AccessTools2.Method returned null (TaleWorlds API not present in this build)");
            return;
        }
        try
        {
            harmony.Patch(target, finalizer: new HarmonyMethod(FinalizerMethod, before: BEW));
            DiagLog("BEWPatch", label + " bound -- finalizer active on " + target.DeclaringType?.FullName + "." + target.Name);
        }
        catch (Exception ex)
        {
            DiagLog("BEWPatch", label + " bind threw " + ex.GetType().Name + ": " + ex.Message);
        }
    }

    internal static void Enable(Harmony harmony)
    {
        // Per-patch defensive bind: a single missing MethodInfo (e.g. if a
        // beta-branch TaleWorlds API rename hides one) used to blow up the
        // whole call chain because Harmony.Patch(null,...) throws NRE before
        // the remaining four patches get a chance. Now each binds or skips
        // independently and reports its outcome via CrestDiag so
        // CrestPatchSelfTest's "OK / HARD" verdicts are traceable to which
        // method went missing.
        DiagLog("BEWPatch", "Enable() invoked -- attempting 5 finalizer binds");
        TryPatchOne(harmony, ManagedApplicationTickMethod,           "Managed.ApplicationTick");
        TryPatchOne(harmony, ModuleOnApplicationTickMethod,          "Module.OnApplicationTick");
        TryPatchOne(harmony, ScreenManagerTickMethod,                "ScreenManager.Tick");
        TryPatchOne(harmony, ManagedScriptHolderTickComponentsMethod,"ManagedScriptHolder.TickComponents");
        TryPatchOne(harmony, MissionTickMethod,                      "Mission.Tick");

        // Managed.ApplicationTick
        harmony.TryPatch(
            AccessTools2.Method("ManagedCallbacks.LibraryCallbacksGenerated:Managed_ApplicationTick"),
            transpiler: AccessTools2.Method(typeof(BEWPatch), nameof(BlankTranspiler)));
        // ScreenManager.Tick
        harmony.TryPatch(
            AccessTools2.Method("ManagedCallbacks.EngineCallbacksGenerated:ScreenManager_Tick") ??
            AccessTools2.Method("ManagedCallbacks.EngineCallbacksGenerated:EngineScreenManager_Tick"),
            transpiler: AccessTools2.Method(typeof(BEWPatch), nameof(BlankTranspiler)));
        // ManagedScriptHolder.TickComponents
        harmony.TryPatch(
            AccessTools2.Method("ManagedCallbacks.EngineCallbacksGenerated:ManagedScriptHolder_TickComponents"),
            transpiler: AccessTools2.Method(typeof(BEWPatch), nameof(BlankTranspiler)));
        // Mission.Tick
        harmony.TryPatch(
            AccessTools2.Method("TaleWorlds.MountAndBlade.MissionState:FinishMissionLoading"),
            transpiler: AccessTools2.Method(typeof(BEWPatch), nameof(BlankTranspiler)));
        harmony.TryPatch(
            AccessTools2.Method("TaleWorlds.MountAndBlade.MissionState:TickMissionAux"),
            transpiler: AccessTools2.Method(typeof(BEWPatch), nameof(BlankTranspiler)));
        harmony.TryPatch(
            AccessTools2.Method("TaleWorlds.MountAndBlade.MissionState:TickMission"),
            transpiler: AccessTools2.Method(typeof(BEWPatch), nameof(BlankTranspiler)));
    }

    internal static void Disable(Harmony harmony)
    {
        harmony.Unpatch(ManagedApplicationTickMethod, FinalizerMethod);
        harmony.Unpatch(ModuleOnApplicationTickMethod, FinalizerMethod);
        harmony.Unpatch(ScreenManagerTickMethod, FinalizerMethod);
        harmony.Unpatch(ManagedScriptHolderTickComponentsMethod, FinalizerMethod);
        harmony.Unpatch(MissionTickMethod, FinalizerMethod);
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static IEnumerable<CodeInstruction> BlankTranspiler(IEnumerable<CodeInstruction> instructions) => instructions;
}