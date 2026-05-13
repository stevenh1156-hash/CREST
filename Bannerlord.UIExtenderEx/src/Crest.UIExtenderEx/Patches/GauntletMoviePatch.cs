using HarmonyLib;
using HarmonyLib.BUTR.Extensions;

using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;

using TaleWorlds.GauntletUI.BaseTypes;
using TaleWorlds.GauntletUI.PrefabSystem;
using TaleWorlds.Library;

namespace Bannerlord.UIExtenderEx.Patches;

internal static class GauntletMoviePatch
{
    private static readonly ConcurrentDictionary<UIExtenderRuntime, List<string>> _widgetNames = new();
    private static readonly ConcurrentDictionary<Type, Type[]> _widgetChildCache = new();
    private static readonly AccessTools.FieldRef<GeneratedPrefabContext, Dictionary<string, Dictionary<string, CreateGeneratedWidget>>>? _generatedPrefabs =
        AccessTools2.FieldRefAccess<GeneratedPrefabContext, Dictionary<string, Dictionary<string, CreateGeneratedWidget>>>("_generatedPrefabs");

    public static void Register(UIExtenderRuntime runtime, string? autoGenWidgetName)
    {
        if (string.IsNullOrEmpty(autoGenWidgetName))
            return;

        _widgetNames.AddOrUpdate(runtime, _ => [autoGenWidgetName], (_, list) =>
        {
            list.Add(autoGenWidgetName!);
            return list;
        });
    }

    public static void Deregister(UIExtenderRuntime runtime)
    {
        _widgetNames.TryRemove(runtime, out var _);
    }

    public static void Patch(Harmony harmony)
    {
        // CREST v0.9.4 fix: bind GauntletMovie.Load by signature shape, not by
        // parameter name. Original implementation required a parameter literally
        // named "doNotUseGeneratedPrefabs"; TaleWorlds renamed/reshaped that on
        // the e1.4.x beta branch and the patch silently skipped.
        //
        // v0.9.4b: shape detection wasn't matching either. Add diag logging so
        // we see the ACTUAL signature on disk, then pick whichever Load method
        // has a `ref bool` parameter anywhere in its parameter list and bind to
        // that position dynamically.
        var mi = AccessTools2.DeclaredMethod("TaleWorlds.GauntletUI.Data.GauntletMovie:Load");
        if (mi == null)
        {
            DiagLog("Patch: TaleWorlds.GauntletUI.Data.GauntletMovie:Load not found via AccessTools2.DeclaredMethod");
            return;
        }

        var pars = mi.GetParameters();
        // Log the full signature we see so future signature drift is visible in runtime.log.
        var sigDump = string.Join(", ", pars.Select(p => $"[{p.Position}] {p.ParameterType.FullName} {p.Name}"));
        DiagLog($"Patch: Load signature observed = ({sigDump})");

        // Find the index of any `ref bool` parameter. On v1.3.x and earlier
        // v1.4.x betas this was at index 3 with name doNotUseGeneratedPrefabs.
        var refBoolIdx = -1;
        for (var i = 0; i < pars.Length; i++)
        {
            if (pars[i].ParameterType == typeof(bool).MakeByRefType())
            {
                refBoolIdx = i;
                break;
            }
        }
        if (refBoolIdx < 0)
        {
            DiagLog("Patch: no `ref bool` parameter on Load; cannot bind prefix this branch.");
            return;
        }

        DiagLog($"Patch: binding LoadPrefix; ref-bool param is at index {refBoolIdx}");
        harmony.Patch(
            mi,
            prefix: new HarmonyMethod(typeof(GauntletMoviePatch), nameof(LoadPrefix)));
    }

    /// <summary>
    /// Mirror a line into Modules\CREST\runtime.log via reflection into
    /// Bannerlord.Harmony.CrestDiag. Same pattern used by ExceptionReporter +
    /// BEWPatch -- keeps this file compile-time-independent of Crest.Harmony.
    /// </summary>
    private static void DiagLog(string message)
    {
        try
        {
            var crestDiagType = Type.GetType("Bannerlord.Harmony.CrestDiag, Crest.Harmony");
            var logMethod = crestDiagType?.GetMethod("Log",
                System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static,
                null,
                new[] { typeof(string), typeof(string) },
                null);
            logMethod?.Invoke(null, new object[] { "GauntletMoviePatch", message });
        }
        catch { /* never throw from diagnostic logging */ }
    }

    // Positional Harmony bindings via [HarmonyArgument(N)]. Parameter names on
    // this side are decorative; Harmony binds by index from the target method.
    // Index 3 is the bool-by-ref `doNotUseGeneratedPrefabs` (or whatever the
    // current beta calls it).
    private static void LoadPrefix(
        [HarmonyArgument(0)] WidgetFactory widgetFactory,
        [HarmonyArgument(1)] string movieName,
        [HarmonyArgument(2)] IViewModel? datasource,
        [HarmonyArgument(3)] ref bool doNotUseGeneratedPrefabs)
    {
        static IEnumerable<string> GetAllInvolvedAutoGenNames(WidgetFactory widgetFactory, string movieName, IViewModel? datasource)
        {
            static IEnumerable<Type> GetChildWidgets(Type widgetType)
            {
                var children = _widgetChildCache.GetOrAdd(widgetType, static x => x.GetFields(AccessTools.all).Select(x => x.FieldType).Where(x => x.IsSubclassOf(typeof(Widget))).Distinct().ToArray());
                foreach (var childWidgetType in children.Where(x => x != widgetType))
                {
                    foreach (var childChildWidgetType in GetChildWidgets(childWidgetType).Where(x => x != widgetType && x != childWidgetType))
                    {
                        yield return childChildWidgetType;
                    }
                }
            }

            if (_generatedPrefabs?.Invoke(widgetFactory.GeneratedPrefabContext) is { } generatedPrefabs)
            {
                const string create = "Create";
                var variantName = datasource != null ? datasource.GetType().FullName : "Default";
                if (generatedPrefabs.TryGetValue(movieName, out var dict2) && dict2.TryGetValue(variantName, out var creator) && AccessTools2.TypeByName(creator.Method.Name.Remove(0, create.Length)) is { } type)
                {
                    var widgets = new List<Type> { type }.Concat(GetChildWidgets(type));
                    var widgetNames = widgets.Select(x => x.Name);
                    var autoGenNames = widgetNames.Where(x => x.Contains("__"));
                    return autoGenNames.Select(x => x.Split(["__"], StringSplitOptions.None)[0]);
                }
            }
            /* This implementation actually created the Widget, but it seems that game didn't intend for that
            var variantName = datasource == null ? "Default" : datasource.GetType().FullName;
            var data = datasource == null ? new Dictionary<string, object>() : new() { {"DataSource", datasource} };
            if (widgetFactory.GeneratedPrefabContext.InstantiatePrefab(context, movieName, variantName, data) is { } autogenResult)
            {
                var autoGen = autogenResult.Root;
                autoGen.DisableRender = true;
                autoGen.IsVisible = false;
                autoGen.UpdateChildrenStates = false;
                var widgetNames = new HashSet<string> { autoGen.GetType().Name };
                CheckChildrenAutoGens(ref widgetNames, autoGen);
                var autoGenNames = widgetNames.Where(x => x.Contains("__")).ToArray();
                return autoGenNames.Select(x => x.Split(["__"], StringSplitOptions.None)[0]);
            }
            */

            return Enumerable.Empty<string>();
        }

        var moviesPatched = new HashSet<string>(UIExtender.GetAllRuntimes().SelectMany(x => x.PrefabComponent.GetMoviesToPatch()));
        var moviesInvolved = new HashSet<string>(GetAllInvolvedAutoGenNames(widgetFactory, movieName, datasource));
        if (moviesInvolved.Overlaps(moviesPatched))
            doNotUseGeneratedPrefabs = true;

        var moviesBlacklisted = _widgetNames.SelectMany(kv => kv.Value);
        if (moviesBlacklisted.Contains(movieName))
            doNotUseGeneratedPrefabs = true;
    }
}