using HarmonyLib;
using HarmonyLib.BUTR.Extensions;

using System;
using System.Collections.Generic;

namespace Bannerlord.BLSE.Shared;

/// <summary>
/// CREST Phase N companion patch (TaleWorlds-side). Hides the four CREST stub
/// modules from the BARE TaleWorlds launcher's mod list -- the launcher you
/// see when Steam launches <c>TaleWorlds.MountAndBlade.Launcher.exe</c>
/// directly without going through <c>Bannerlord.BLSE.LauncherEx.exe</c>.
///
/// The BUTR-side stub-hide patch (in <c>Bannerlord.LauncherEx.Patches.HideCrestStubsPatch</c>)
/// only fires when <c>Manager.Enable()</c> runs, which only happens when the
/// user launches via the LauncherEx exe. The Steam path goes through
/// <c>Shared.AppDomainManager.Initialize()</c> only -- no Manager.Enable, no
/// BUTR mixin, no patches against BUTRLauncherModuleVM.
///
/// To cover the Steam path we patch the TaleWorlds launcher's own
/// <c>LauncherModsVM.IsVisible(bool isMultiplayer, ModuleInfo moduleInfo)</c>
/// predicate, returning false unconditionally for our four stub IDs. The
/// launcher uses this method to decide which modules to render in its mod
/// list -- making it return false hides the stubs cleanly without changing
/// any underlying state, so dependency resolution still finds them.
///
/// Both patches coexist safely: when launching via LauncherEx, both fire (the
/// BUTR-side removes the stubs from BUTR's Modules2 collection; this one
/// makes the underlying TaleWorlds IsVisible return false too). When launching
/// via Steam, only this one fires.
///
/// Diagnostic escape hatch: set environment variable <c>CREST_SHOW_STUBS=1</c>
/// before launching to bring the stubs back into view.
/// </summary>
public static class HideCrestStubsFromTaleWorldsLauncher
{
    private static readonly string[] StubIds =
    {
        "Bannerlord.Harmony",
        "Bannerlord.ButterLib",
        "Bannerlord.UIExtenderEx",
        "Bannerlord.MBOptionScreen",
    };

    private static HashSet<string>? _stubIdSet;
    private static HashSet<string> StubIdSet => _stubIdSet ??= new HashSet<string>(StubIds, StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// Reflection accessor for ModuleInfo.Id. Computed lazily on first patch
    /// invocation because TaleWorlds.ModuleManager.dll may not be loaded
    /// yet when this class's static cctor runs.
    /// </summary>
    private static System.Reflection.PropertyInfo? _moduleInfoIdGetter;

    public static void Enable(Harmony harmony)
    {
        try { EnableInner(harmony); }
        catch
        {
            // Top-level safety: a failure here must NEVER break the launcher.
            // Stubs visible is a much better failure mode than no launcher.
        }
    }

    private static Harmony? _harmony;
    private static bool _patchApplied;

    private static void EnableInner(Harmony harmony)
    {
        if (string.Equals(Environment.GetEnvironmentVariable("CREST_SHOW_STUBS"), "1", StringComparison.Ordinal))
            return;

        _harmony = harmony;

        // Try immediately in case the assembly is already loaded.
        if (TryApplyPatch()) return;

        // Otherwise, defer: register an AssemblyLoad handler that retries
        // when TaleWorlds.MountAndBlade.Launcher.Library loads. AppDomainManager.Initialize
        // runs very early in launcher startup, before TaleWorlds.MountAndBlade.Launcher.Library.dll
        // is loaded into the AppDomain, so type-resolution will fail at first.
        AppDomain.CurrentDomain.AssemblyLoad += OnAssemblyLoad;
    }

    private static void OnAssemblyLoad(object? sender, AssemblyLoadEventArgs args)
    {
        try
        {
            var name = args.LoadedAssembly.GetName().Name;
            if (name == "TaleWorlds.MountAndBlade.Launcher.Library" || name == "TaleWorlds.ModuleManager")
            {
                if (TryApplyPatch())
                    AppDomain.CurrentDomain.AssemblyLoad -= OnAssemblyLoad;
            }
        }
        catch
        {
            // Never let an exception in this handler propagate -- it would
            // surface as an unhandled domain event during launcher startup.
        }
    }

    private static bool TryApplyPatch()
    {
        if (_patchApplied || _harmony == null) return _patchApplied;
        try
        {
            var modsVmType = AccessTools2.TypeByName("TaleWorlds.MountAndBlade.Launcher.Library.LauncherModsVM");
            if (modsVmType == null) return false;

            var moduleInfoType = AccessTools2.TypeByName("TaleWorlds.ModuleManager.ModuleInfo");
            if (moduleInfoType == null) return false;

            var isVisibleMethod = AccessTools2.Method(modsVmType, "IsVisible", new[] { typeof(bool), moduleInfoType });
            if (isVisibleMethod == null) return false;

            _harmony.Patch(isVisibleMethod,
                postfix: new HarmonyMethod(AccessTools2.DeclaredMethod(typeof(HideCrestStubsFromTaleWorldsLauncher), nameof(IsVisiblePostfix))));
            _patchApplied = true;
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Postfix coerces <c>__result = false</c> when the moduleInfo's Id
    /// matches one of our four stub IDs. ModuleInfo.Id access uses
    /// reflection because we don't reference TaleWorlds.ModuleManager.dll
    /// directly from BLSE.Shared.
    /// </summary>
    private static void IsVisiblePostfix(object moduleInfo, ref bool __result)
    {
        if (!__result) return;        // already hidden
        if (moduleInfo == null) return;
        try
        {
            if (_moduleInfoIdGetter == null)
                _moduleInfoIdGetter = moduleInfo.GetType().GetProperty("Id");
            var id = _moduleInfoIdGetter?.GetValue(moduleInfo) as string;
            if (id != null && StubIdSet.Contains(id))
                __result = false;
        }
        catch
        {
            // Defensive: if the reflection fails for any reason, leave
            // __result alone so the launcher renders the module normally.
        }
    }
}
