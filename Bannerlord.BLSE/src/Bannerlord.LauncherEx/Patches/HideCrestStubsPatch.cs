using Bannerlord.LauncherEx.Mixins;
using Bannerlord.LauncherEx.ViewModels;

using HarmonyLib;
using HarmonyLib.BUTR.Extensions;

using System;
using System.Collections.Generic;
using System.Linq;

namespace Bannerlord.LauncherEx.Patches;

/// <summary>
/// Phase N companion patch: hides the four CREST stub modules from the
/// launcher's mod list UI by force-setting their <see cref="BUTRLauncherModuleVM.IsVisible"/>
/// to false at every code path that sets it true.
///
/// Why setter+SetViewModels postfix and not getter postfix:
///   - The launcher binds <c>IsVisible</c> via BUTR's <c>[BUTRDataSourceProperty]</c>
///     attribute. That binding system uses an emitted-IL data-source proxy that
///     reads the BACKING FIELD directly, not the getter. A getter postfix
///     therefore has no effect on what the UI displays.
///   - The setter, however, is called from every code path that wants to
///     change visibility (constructor default, search-text refresh, drag-drop
///     reorder). Hooking the setter lets us coerce true to false at the
///     source. Combined with a one-time pass when SetViewModels finishes
///     populating Modules2, every stub VM ends up with the field set to false.
///
/// Stubs themselves stay in <c>ExtendedModuleInfoCache</c> -- only their
/// VM-level visibility flips. Dependency resolution, load-order sorting, and
/// engine module-presence checks all still see the stubs as present, so
/// community mods' <c>&lt;DependedModule Id="Bannerlord.Harmony"/&gt;</c>
/// (etc.) checks pass exactly as before.
///
/// Deployment note: BLSE embeds Bannerlord.LauncherEx.dll as a gzipped resource
/// inside Bannerlord.BLSE.Shared.dll. If a stale copy of Bannerlord.LauncherEx.dll
/// exists on disk in <c>bin\Win64_Shipping_Client\</c>, that on-disk copy wins
/// over the embedded one and patches in this class won't fire. Always remove
/// the on-disk DLL when redeploying BLSE.Shared.
///
/// To re-enable the stubs in the launcher (debugging), set environment
/// variable <c>CREST_SHOW_STUBS=1</c> before launching the game.
/// </summary>
internal static class HideCrestStubsPatch
{
    private static readonly string[] StubIdArray =
    {
        "Bannerlord.Harmony",
        "Bannerlord.ButterLib",
        "Bannerlord.UIExtenderEx",
        "Bannerlord.MBOptionScreen",
    };

    private static HashSet<string>? _stubIds;
    private static HashSet<string> StubIds => _stubIds ??= new HashSet<string>(StubIdArray, StringComparer.OrdinalIgnoreCase);

    public static void Enable(Harmony harmony)
    {
        try { EnableInner(harmony); }
        catch
        {
            // Top-level safety: a failure in this patch must NEVER break
            // launcher startup. The user seeing four stub rows in the mod
            // list is a much better failure mode than the launcher refusing
            // to render at all.
        }
    }

    private static void EnableInner(Harmony harmony)
    {
        // Diagnostic escape hatch -- developer can set this env var to bring
        // stubs back into the UI temporarily.
        if (string.Equals(Environment.GetEnvironmentVariable("CREST_SHOW_STUBS"), "1", StringComparison.Ordinal))
            return;

        // (1) Setter prefix -- intercepts every IsVisible = X assignment.
        // Patch the property setter (the BUTR data-source proxy reads the
        // backing field, but other code paths set via the property; setting
        // via the property fires INotifyPropertyChanged so the binding
        // re-reads).
        var setter = AccessTools2.DeclaredPropertySetter(typeof(BUTRLauncherModuleVM), nameof(BUTRLauncherModuleVM.IsVisible));
        if (setter != null)
        {
            try
            {
                harmony.Patch(setter,
                    prefix: new HarmonyMethod(AccessTools2.DeclaredMethod(typeof(HideCrestStubsPatch), nameof(IsVisibleSetterPrefix))));
            }
            catch { }
        }

        // (2) SetViewModels postfix -- after Modules2 is (re)populated by
        // the launcher, walk it and force every stub VM's IsVisible = false.
        // This handles the constructor's _isVisible=true field initializer
        // (which the setter prefix can't see) plus every refresh path.
        var setVms = AccessTools2.DeclaredMethod(typeof(LauncherModsVMMixin), "SetViewModels");
        if (setVms != null)
        {
            try
            {
                harmony.Patch(setVms,
                    postfix: new HarmonyMethod(AccessTools2.DeclaredMethod(typeof(HideCrestStubsPatch), nameof(SetViewModelsPostfix))));
            }
            catch { }
        }
    }

    private static bool IsVisibleSetterPrefix(BUTRLauncherModuleVM __instance, ref bool value)
    {
        if (!value) return true; // setting to false: always allow
        try
        {
            var id = __instance.ModuleInfoExtended?.Id;
            if (id != null && StubIds.Contains(id)) value = false;
        }
        catch { /* never block the original setter */ }
        return true;
    }

    /// <summary>
    /// After Modules2 is (re)populated by the launcher, REMOVE the four stub
    /// VMs from the visible collection. Setting <c>IsVisible = false</c>
    /// alone doesn't suppress them because BUTR's data-source proxy reads
    /// via a generated path that doesn't honor INotifyPropertyChanged on
    /// IsVisible the way the BindingList rendering does. Removing from
    /// Modules2 is reliable.
    ///
    /// Safe to remove from Modules2 because dependency validation uses
    /// LauncherModsVMMixin._modulesLookup (a separate dictionary that still
    /// contains the stubs) for &lt;DependedModule Id&gt; resolution.
    /// SetViewModels clears+repopulates Modules2 on every refresh, so this
    /// postfix runs again each time and re-removes any reintroduced stubs.
    /// </summary>
    private static void SetViewModelsPostfix(LauncherModsVMMixin __instance)
    {
        try
        {
            var toRemove = __instance.Modules2.OfType<BUTRLauncherModuleVM>()
                .Where(vm => vm.ModuleInfoExtended?.Id is string id && StubIds.Contains(id))
                .ToList();
            foreach (var vm in toRemove) __instance.Modules2.Remove(vm);
        }
        catch { /* never break the launcher's mod list refresh */ }
    }
}
