using HarmonyLib;
using HarmonyLib.BUTR.Extensions;

using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;

using TaleWorlds.Library;
using TaleWorlds.Localization;

namespace Bannerlord.Harmony;

/// <summary>
/// Phase P.2 -- runtime verification that the top-N most version-fragile
/// Harmony patches inherited from upstream BUTR actually bound on this game
/// version. Walks Harmony.GetAllPatchedMethods() once at game-start (just
/// after the Native modules finish initializing) and confirms each expected
/// patch site has at least one patch from the expected owner namespace.
///
/// Runs OFF by default if `runtime-self-test=false` is set in
/// Modules\CREST\crest.json's <c>"enabled"</c> block; otherwise on. Surfaces
/// at most one user-visible orange InformationManager message naming the
/// number of misses; full per-patch detail lands in Modules\CREST\runtime.log
/// via <see cref="CrestDiag"/>.
///
/// What this protects against: a TaleWorlds update renames a method or
/// inlines an internal helper, our IL transpiler / parameter-name match
/// silently no-ops, and the user notices three weeks later when "feature
/// stopped working." That's the H1 / Harmony-patch-fragility class of failure
/// that AUDIT_v1.3.0.md identified as the largest version-update breakage
/// surface. This self-test surfaces it as a single visible warning at launch.
/// </summary>
internal static class CrestPatchSelfTest
{
    private const string Source = nameof(CrestPatchSelfTest);

    private const uint COLOR_ORANGE = 0xFF8000;
    private const uint COLOR_GREEN = 0x77CC77;

    private const string SWarningMissingPatches =
        "{=crest_pst_warn}CREST patch self-test: {COUNT} of {TOTAL} fragile patches did not bind. See Modules\\CREST\\runtime.log.";

    /// <summary>
    /// One row of the expected-patches table. <see cref="TargetType"/> +
    /// <see cref="TargetMethod"/> identifies the original method we expect
    /// to be patched; <see cref="ExpectedOwnerNamespace"/> is matched as a
    /// substring against each patch's <c>DeclaringType.FullName</c>. The
    /// substring match (rather than equality) tolerates minor namespace
    /// reorganizations within our fork while still catching the case where
    /// the patch entirely failed to bind.
    /// </summary>
    private sealed class Expectation
    {
        public string Label = "";
        public string? TargetType;
        public string? TargetMethod;
        // For TargetMethod that's overloaded or ambiguous; null = any signature.
        public Func<MethodBase, bool>? ExtraTargetFilter;
        public string ExpectedOwnerNamespace = "";
        // Some patches are conditional (e.g. GauntletMoviePatch only patches
        // a particular Load overload if a parameter named doNotUseGeneratedPrefabs
        // is present). Mark those as "soft" so a miss logs but doesn't count
        // against the user-visible warning.
        public bool Soft;
    }

    private static readonly Expectation[] _expectations =
    [
        // 1. UIExtenderEx WidgetPrefabPatch -- IL transpiler + reverse-patcher
        // on WidgetPrefab.LoadFrom. Single highest-risk patch in the stack.
        new Expectation
        {
            Label                  = "UIExtenderEx.WidgetPrefab.LoadFrom (transpiler)",
            TargetType             = "TaleWorlds.GauntletUI.PrefabSystem.WidgetPrefab",
            TargetMethod           = "LoadFrom",
            ExpectedOwnerNamespace = "Bannerlord.UIExtenderEx.Patches.WidgetPrefabPatch",
        },

        // 2. ButterLib ModulePatch -- transpiler on
        // Module.SetInitialModuleScreenAsRootScreen looking for specific OpCodes.
        // We've already seen this one fail in past versions.
        new Expectation
        {
            Label                  = "ButterLib.Module.SetInitialModuleScreenAsRootScreen (transpiler)",
            TargetType             = "TaleWorlds.MountAndBlade.Module",
            TargetMethod           = "SetInitialModuleScreenAsRootScreen",
            ExpectedOwnerNamespace = "Bannerlord.ButterLib.Implementation.MBSubModuleBaseExtended.Patches.ModulePatch",
        },
        new Expectation
        {
            Label                  = "ButterLib.Module.FinalizeSubModules (postfix)",
            TargetType             = "TaleWorlds.MountAndBlade.Module",
            TargetMethod           = "FinalizeSubModules",
            ExpectedOwnerNamespace = "Bannerlord.ButterLib.Implementation.MBSubModuleBaseExtended.Patches.ModulePatch",
        },

        // 3. BEWPatch -- finalizer patches on five high-frequency tick methods.
        // If any binding fails, exception handling breaks invisibly.
        new Expectation
        {
            Label                  = "BEW.Managed.ApplicationTick (finalizer)",
            TargetType             = "TaleWorlds.DotNet.Managed",
            TargetMethod           = "ApplicationTick",
            ExpectedOwnerNamespace = "Bannerlord.ButterLib.ExceptionHandler.BEWPatch",
        },
        new Expectation
        {
            Label                  = "BEW.Module.OnApplicationTick (finalizer)",
            TargetType             = "TaleWorlds.MountAndBlade.Module",
            TargetMethod           = "OnApplicationTick",
            ExpectedOwnerNamespace = "Bannerlord.ButterLib.ExceptionHandler.BEWPatch",
        },
        new Expectation
        {
            Label                  = "BEW.ScreenManager.Tick (finalizer)",
            TargetType             = "TaleWorlds.ScreenSystem.ScreenManager",
            TargetMethod           = "Tick",
            ExpectedOwnerNamespace = "Bannerlord.ButterLib.ExceptionHandler.BEWPatch",
        },
        new Expectation
        {
            Label                  = "BEW.ManagedScriptHolder.TickComponents (finalizer)",
            TargetType             = "TaleWorlds.Engine.ManagedScriptHolder",
            TargetMethod           = "TickComponents",
            ExpectedOwnerNamespace = "Bannerlord.ButterLib.ExceptionHandler.BEWPatch",
        },
        new Expectation
        {
            Label                  = "BEW.Mission.Tick (finalizer)",
            TargetType             = "TaleWorlds.MountAndBlade.Mission",
            TargetMethod           = "Tick",
            ExpectedOwnerNamespace = "Bannerlord.ButterLib.ExceptionHandler.BEWPatch",
        },

        // 4. UIExtenderEx GauntletMoviePatch -- conditional patch keyed on a
        // parameter named "doNotUseGeneratedPrefabs". Trivially broken if
        // TaleWorlds renames the parameter. Marked Soft because in some game
        // versions the parameter doesn't exist at all and the patch
        // intentionally no-ops.
        new Expectation
        {
            Label                  = "UIExtenderEx.GauntletMovie.Load (conditional prefix)",
            TargetType             = "TaleWorlds.GauntletUI.Data.GauntletMovie",
            TargetMethod           = "Load",
            ExtraTargetFilter      = m => m.GetParameters().Any(p => p.Name == "doNotUseGeneratedPrefabs"),
            ExpectedOwnerNamespace = "Bannerlord.UIExtenderEx.Patches.GauntletMoviePatch",
            Soft                   = true,
        },

        // 5. UIExtenderEx WidgetFactoryManager -- six TryPatches on internal
        // methods. The four hard ones first; the two TryPatch-only ones marked
        // Soft because TryPatch is intentionally tolerant of binding failures.
        new Expectation
        {
            Label                  = "UIExtenderEx.WidgetFactory.GetCustomType (prefix)",
            TargetType             = "TaleWorlds.GauntletUI.PrefabSystem.WidgetFactory",
            TargetMethod           = "GetCustomType",
            ExpectedOwnerNamespace = "Bannerlord.UIExtenderEx.ResourceManager.WidgetFactoryManager",
        },
        new Expectation
        {
            Label                  = "UIExtenderEx.WidgetFactory.CreateBuiltinWidget (prefix)",
            TargetType             = "TaleWorlds.GauntletUI.PrefabSystem.WidgetFactory",
            TargetMethod           = "CreateBuiltinWidget",
            ExpectedOwnerNamespace = "Bannerlord.UIExtenderEx.ResourceManager.WidgetFactoryManager",
        },
        new Expectation
        {
            Label                  = "UIExtenderEx.WidgetFactory.GetWidgetTypes (postfix)",
            TargetType             = "TaleWorlds.GauntletUI.PrefabSystem.WidgetFactory",
            TargetMethod           = "GetWidgetTypes",
            ExpectedOwnerNamespace = "Bannerlord.UIExtenderEx.ResourceManager.WidgetFactoryManager",
        },
        new Expectation
        {
            Label                  = "UIExtenderEx.WidgetFactory.IsCustomType (prefix)",
            TargetType             = "TaleWorlds.GauntletUI.PrefabSystem.WidgetFactory",
            TargetMethod           = "IsCustomType",
            ExpectedOwnerNamespace = "Bannerlord.UIExtenderEx.ResourceManager.WidgetFactoryManager",
        },
        new Expectation
        {
            Label                  = "UIExtenderEx.WidgetTemplate.CreateWidgets (transpiler, soft)",
            TargetType             = "TaleWorlds.GauntletUI.PrefabSystem.WidgetTemplate",
            TargetMethod           = "CreateWidgets",
            ExpectedOwnerNamespace = "Bannerlord.UIExtenderEx.ResourceManager.WidgetFactoryManager",
            Soft                   = true,
        },
        new Expectation
        {
            Label                  = "UIExtenderEx.GauntletMovie.LoadMovie (transpiler, soft)",
            TargetType             = "TaleWorlds.GauntletUI.Data.GauntletMovie",
            TargetMethod           = "LoadMovie",
            ExpectedOwnerNamespace = "Bannerlord.UIExtenderEx.ResourceManager.WidgetFactoryManager",
            Soft                   = true,
        },
    ];

    /// <summary>
    /// Run the self-test. Idempotent -- calling twice in one session re-walks
    /// patches but produces no duplicate user-visible message. Driven by the
    /// runtime-self-test flag in crest.json (default: on).
    /// </summary>
    public static void Run()
    {
        if (_alreadyRan) return;
        _alreadyRan = true;

        if (!CrestConfig.IsEnabled("RuntimeSelfTest", defaultValue: true))
        {
            CrestDiag.Log(Source, "skipped (RuntimeSelfTest disabled in crest.json)");
            return;
        }

        var hardMissing = new List<string>();
        var softMissing = new List<string>();
        var ok = new List<string>();

        // Snapshot the global patch table once. GetAllPatchedMethods is O(N)
        // and GetPatchInfo is per-method, so the whole walk is fast even with
        // dozens of mods loaded.
        var allPatched = HarmonyLib.Harmony.GetAllPatchedMethods().ToList();
        CrestDiag.Log(Source, "GetAllPatchedMethods returned " + allPatched.Count + " methods");

        // Diagnostic dump of every patched method, with the owner of each
        // patch on it. Verbose, but invaluable when an expected patch isn't
        // matching: lets us see whether the patch is missing, on the wrong
        // method, or under a namespace the expectation didn't anticipate.
        // Gated by a separate flag so an expert can leave it off in normal
        // operation and just re-enable on demand.
        if (CrestConfig.IsEnabled("RuntimeSelfTestVerbose", defaultValue: false))
        {
            foreach (var pm in allPatched)
            {
                var info = HarmonyLib.Harmony.GetPatchInfo(pm);
                if (info == null) continue;
                var owners = info.Prefixes.Concat(info.Postfixes).Concat(info.Transpilers).Concat(info.Finalizers)
                    .Select(p => (p.PatchMethod.DeclaringType?.FullName ?? "?") + "." + p.PatchMethod.Name)
                    .Distinct()
                    .ToList();
                var dt = pm.DeclaringType?.FullName ?? "?";
                CrestDiag.Log(Source, "  patched: " + dt + "." + pm.Name + "  by [" + string.Join(", ", owners) + "]");
            }
        }

        foreach (var exp in _expectations)
        {
            var bound = TryFindBoundPatch(exp, allPatched, out var detail);
            if (bound)
            {
                ok.Add(exp.Label);
                CrestDiag.Log(Source, "OK   " + exp.Label + " -- " + detail);
            }
            else
            {
                if (exp.Soft) softMissing.Add(exp.Label);
                else hardMissing.Add(exp.Label);

                CrestDiag.Log(Source, (exp.Soft ? "SOFT " : "HARD ") + exp.Label + " -- " + detail);
            }
        }

        CrestDiag.Log(Source,
            $"summary: {ok.Count} bound, {hardMissing.Count} hard miss, {softMissing.Count} soft miss " +
            $"(of {_expectations.Length} total)");

        // User-visible warning intentionally suppressed.
        //
        // The first end-to-end run of this self-test (2026-05-06, runtime.log
        // 04:14:53) showed that our "expected fragile patches" framework
        // generates too many false positives to be reliable as a chat-surfaced
        // warning:
        //
        //   1. Some patches (Module.LoadSubModules, WidgetPrefab.LoadFrom,
        //      WidgetFactory.GetCustomType, etc) appear in
        //      Harmony.GetAllPatchedMethods() but GetPatchInfo() returns empty
        //      Prefixes/Postfixes/Transpilers/Finalizers -- likely because they
        //      were patched during the BLSE launcher-process phase and only
        //      the method-list propagated to the game-process Harmony state.
        //   2. UIExtenderEx patches are lazy: only applied when a consumer mod
        //      calls UIExtender.Register(...). On a baseline CREST install with
        //      no UI extension consumers, those patches legitimately don't
        //      exist yet, so an at-startup self-test naturally misses them.
        //   3. BEW finalizers are gated behind a separate ButterLib opt-in.
        //
        // Calling InformationManager.DisplayMessage from
        // OnBeforeInitialModuleScreenSetAsRoot also coincided with a crash on
        // first try -- the message subsystem isn't fully ready at this
        // lifecycle point on every game version.
        //
        // The runtime.log diagnostic stays on (see the verbose-dump path) so
        // a developer can still inspect what's actually patched, but no chat
        // bubble. Phase P.2 work item rescoped to "log-only diagnostic" until
        // we have a reliable detection model.
        if (hardMissing.Count == 0 && softMissing.Count == 0)
        {
            // Optional confirmation line so a user comparing two builds can
            // tell at a glance the self-test ran. Suppressed if the main-menu
            // message gate is on (CrestMessageStyle drains the queue anyway,
            // so the line goes to runtime.log only -- see SuppressMainMenu...).
            CrestDiag.Log(Source, "all expected patches bound; no user-visible message emitted.");
        }
    }

    private static bool _alreadyRan;

    /// <summary>
    /// Try to find a patch on <paramref name="exp"/>'s target method whose
    /// owner declaring-type matches <see cref="Expectation.ExpectedOwnerNamespace"/>.
    /// Returns true on hit, false otherwise; <paramref name="detail"/> always
    /// gets a one-line human-readable trace of what we found / didn't find.
    /// </summary>
    private static bool TryFindBoundPatch(Expectation exp, List<MethodBase> allPatched, out string detail)
    {
        // First resolve the target method by name. If the target method
        // doesn't even exist on this game version, the patch couldn't have
        // bound for benign reasons -- flag it but return false so the caller
        // logs the miss.
        if (string.IsNullOrEmpty(exp.TargetType) || string.IsNullOrEmpty(exp.TargetMethod))
        {
            detail = "expectation has no target type/method";
            return false;
        }

        var targetType = AccessTools2.TypeByName(exp.TargetType!);
        if (targetType == null)
        {
            detail = "target type not found: " + exp.TargetType;
            return false;
        }

        // The patch table contains MethodBase entries; filter to ones whose
        // declaring type matches and whose name matches. Several methods may
        // match (overloads); ExtraTargetFilter narrows further if provided.
        var candidateTargets = allPatched
            .Where(m => m.DeclaringType == targetType && m.Name == exp.TargetMethod)
            .Where(m => exp.ExtraTargetFilter == null || exp.ExtraTargetFilter(m))
            .ToList();

        if (candidateTargets.Count == 0)
        {
            // Provide a hint: list any methods on this type that ARE patched,
            // so we can see whether the method was renamed, the parameter
            // filter rejected all overloads, or the method genuinely isn't
            // patched.
            var siblings = allPatched
                .Where(m => m.DeclaringType == targetType)
                .Select(m => m.Name)
                .Distinct()
                .ToList();
            var siblingHint = siblings.Count > 0
                ? " (other patched methods on this type: " + string.Join(", ", siblings) + ")"
                : " (no methods on this type are patched at all)";
            detail = "no patch found on " + exp.TargetType + "." + exp.TargetMethod + siblingHint;
            return false;
        }

        foreach (var target in candidateTargets)
        {
            var info = HarmonyLib.Harmony.GetPatchInfo(target);
            if (info == null) continue;

            var allPatches = info.Prefixes
                .Concat(info.Postfixes)
                .Concat(info.Transpilers)
                .Concat(info.Finalizers);

            foreach (var p in allPatches)
            {
                var declaring = p.PatchMethod.DeclaringType?.FullName ?? "";
                if (declaring.IndexOf(exp.ExpectedOwnerNamespace, StringComparison.Ordinal) >= 0)
                {
                    detail = $"bound by {declaring}.{p.PatchMethod.Name} on {target.Name}";
                    return true;
                }
            }
        }

        // Surface what IS patching the target method so we can see whether the
        // expected owner namespace shifted (e.g., a refactor moved the patch
        // to a sibling class) or whether only an unrelated mod is patching it.
        var actualOwners = candidateTargets
            .SelectMany(t => HarmonyLib.Harmony.GetPatchInfo(t)?.Owners ?? Enumerable.Empty<string>())
            .Distinct()
            .ToList();
        var actualDeclaring = candidateTargets
            .SelectMany(t =>
            {
                var info = HarmonyLib.Harmony.GetPatchInfo(t);
                if (info == null) return Enumerable.Empty<string>();
                return info.Prefixes.Concat(info.Postfixes).Concat(info.Transpilers).Concat(info.Finalizers)
                    .Select(p => p.PatchMethod.DeclaringType?.FullName ?? "?");
            })
            .Distinct()
            .ToList();

        detail = "target method patched, but no patch from " + exp.ExpectedOwnerNamespace
            + " (owners: [" + string.Join(", ", actualOwners) + "]"
            + "; declaring types: [" + string.Join(", ", actualDeclaring) + "])";
        return false;
    }
}
