using HarmonyLib;
using HarmonyLib.BUTR.Extensions;

using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Reflection;

namespace Bannerlord.Harmony;

/// <summary>
/// Phase Y.9: public Harmony-patch helper for CREST-dependent mods.
///
/// Wraps <see cref="HarmonyLib.Harmony.Patch"/> with three layers of safety
/// that consumer mods would otherwise have to write themselves:
///
/// <list type="number">
/// <item><description>
/// <b>Tolerant type/method resolution.</b> Targets are passed as strings
/// (<c>"TaleWorlds.CampaignSystem.Hero"</c>) and resolved via
/// <c>AccessTools2.TypeByName</c>. If the type or method has been renamed/
/// removed in a game update, the helper logs the miss to <c>runtime.log</c>
/// and returns <c>false</c> instead of crashing the SubModule.
/// </description></item>
/// <item><description>
/// <b>Catch-and-log around <c>harmony.Patch</c>.</b> Harmony itself can throw
/// at bind time for arity mismatches, ambiguous overloads, and a few other
/// reasons (the recent RTSCamera ↔ NavalDLC parameter-count crash is the
/// canonical example). SafeBind catches and logs instead of unwinding.
/// </description></item>
/// <item><description>
/// <b>Optional Doctor registration.</b> Patches bound through SafeBind are
/// recorded in a static registry that <c>Crest-Doctor</c> reads when it
/// scans live patches, so consumer-mod patches show up in diagnostic dumps
/// alongside CREST's own. Pass <paramref name="registerWithDoctor"/> = false
/// to opt out (rarely useful).
/// </description></item>
/// </list>
///
/// Typical consumer-mod usage:
///
/// <code>
/// using Bannerlord.Harmony;
///
/// public class SubModule : MBSubModuleBase
/// {
///     private readonly Harmony _harmony = new("MyMod");
///
///     protected override void OnSubModuleLoad()
///     {
///         CrestSafeBind.Patch(_harmony,
///             type: "TaleWorlds.CampaignSystem.Party.MobileParty",
///             method: "CalculateSpeed",
///             postfix: nameof(SpeedPostfix),
///             owner: typeof(SubModule),
///             label: "MyMod.SpeedTweak");
///     }
///
///     public static void SpeedPostfix(ref float __result) =&gt; __result *= 1.10f;
/// }
/// </code>
/// </summary>
public static class CrestSafeBind
{
    private const string Source = nameof(CrestSafeBind);

    // Doctor registry: every successfully-bound patch goes here so the
    // diagnostic tooling can enumerate consumer-mod patches without
    // re-walking Harmony's internal state. Concurrent because mods may
    // bind from multiple threads in their OnSubModuleLoad callbacks.
    private static readonly ConcurrentBag<DoctorPatchEntry> _registry = new();

    /// <summary>
    /// One entry in the Doctor registry. Visible to consumer mods so they
    /// can also enumerate "what's bound by other CREST-dependent mods" if
    /// they want to render their own compat dashboard.
    /// </summary>
    public readonly struct DoctorPatchEntry
    {
        public string OwnerAssembly { get; }
        public string Label { get; }
        public string TargetType { get; }
        public string TargetMethod { get; }
        public string PatchKind { get; }   // "prefix" | "postfix" | "transpiler" | "finalizer"
        public DateTime BoundAt { get; }

        public DoctorPatchEntry(string ownerAssembly, string label, string targetType, string targetMethod, string patchKind, DateTime boundAt)
        {
            OwnerAssembly = ownerAssembly;
            Label = label;
            TargetType = targetType;
            TargetMethod = targetMethod;
            PatchKind = patchKind;
            BoundAt = boundAt;
        }
    }

    /// <summary>Snapshot of every patch successfully bound through <see cref="Patch"/>.</summary>
    public static IReadOnlyCollection<DoctorPatchEntry> GetRegisteredPatches() => _registry.ToArray();

    /// <summary>
    /// Bind a Harmony patch with full error tolerance and Doctor registration.
    /// </summary>
    /// <param name="harmony">Your mod's <see cref="HarmonyLib.Harmony"/> instance.</param>
    /// <param name="type">Fully-qualified target type name (e.g. <c>"TaleWorlds.CampaignSystem.Hero"</c>).</param>
    /// <param name="method">Method name on the target type. Use <c>"get_X"</c> / <c>"set_X"</c> to patch property accessors, <c>".ctor"</c> for constructors.</param>
    /// <param name="prefix">Prefix handler method name (or null).</param>
    /// <param name="postfix">Postfix handler method name (or null).</param>
    /// <param name="transpiler">Transpiler handler method name (or null).</param>
    /// <param name="finalizer">Finalizer handler method name (or null).</param>
    /// <param name="owner">The static class containing the handler method(s). Required so Harmony can resolve the handler MethodInfo.</param>
    /// <param name="label">Short human-readable label used in diagnostic logs and Doctor dumps. Recommended format: <c>"MyMod.FeatureName"</c>.</param>
    /// <param name="registerWithDoctor">If true (default), record success in the Doctor registry.</param>
    /// <returns><c>true</c> if at least one of the four handlers bound successfully.</returns>
    public static bool Patch(
        HarmonyLib.Harmony harmony,
        string type,
        string method,
        string? prefix      = null,
        string? postfix     = null,
        string? transpiler  = null,
        string? finalizer   = null,
        Type?   owner       = null,
        string  label       = "<unlabeled>",
        bool    registerWithDoctor = true)
    {
        if (harmony == null) { CrestDiag.Log(Source, label + ": null harmony instance"); return false; }
        if (string.IsNullOrEmpty(type) || string.IsNullOrEmpty(method))
        {
            CrestDiag.Log(Source, label + ": missing type or method name");
            return false;
        }
        if (owner == null)
        {
            CrestDiag.Log(Source, label + ": owner type is null (handler resolution requires a non-null Type)");
            return false;
        }

        Type? targetType;
        try
        {
            targetType = AccessTools2.TypeByName(type);
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, label + ": TypeByName(" + type + ")", ex);
            return false;
        }
        if (targetType == null)
        {
            CrestDiag.Log(Source, label + ": type not found - " + type);
            return false;
        }

        MethodBase? targetMethod;
        try
        {
            // Constructors get their own resolution path so callers don't need a separate API.
            if (method == ".ctor")
                targetMethod = targetType.GetConstructor(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance, null, Type.EmptyTypes, null);
            else
                targetMethod = AccessTools2.Method(targetType, method);
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, label + ": Method(" + method + ")", ex);
            return false;
        }
        if (targetMethod == null)
        {
            CrestDiag.Log(Source, label + ": method not found - " + type + "." + method);
            return false;
        }

        var prefixM     = prefix     != null ? new HarmonyMethod(owner, prefix)     : null;
        var postfixM    = postfix    != null ? new HarmonyMethod(owner, postfix)    : null;
        var transpilerM = transpiler != null ? new HarmonyMethod(owner, transpiler) : null;
        var finalizerM  = finalizer  != null ? new HarmonyMethod(owner, finalizer)  : null;

        if (prefixM == null && postfixM == null && transpilerM == null && finalizerM == null)
        {
            CrestDiag.Log(Source, label + ": no handlers provided");
            return false;
        }

        try
        {
            harmony.Patch(targetMethod,
                prefix:     prefixM,
                postfix:    postfixM,
                transpiler: transpilerM,
                finalizer:  finalizerM);
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, label + ": harmony.Patch", ex);
            return false;
        }

        if (registerWithDoctor)
        {
            var ownerAsm = owner.Assembly.GetName().Name ?? "(unknown)";
            var now = DateTime.UtcNow;
            if (prefixM     != null) _registry.Add(new DoctorPatchEntry(ownerAsm, label, type, method, "prefix",     now));
            if (postfixM    != null) _registry.Add(new DoctorPatchEntry(ownerAsm, label, type, method, "postfix",    now));
            if (transpilerM != null) _registry.Add(new DoctorPatchEntry(ownerAsm, label, type, method, "transpiler", now));
            if (finalizerM  != null) _registry.Add(new DoctorPatchEntry(ownerAsm, label, type, method, "finalizer",  now));
        }

        CrestDiag.Log(Source, label + ": bound " + type + "." + method);
        return true;
    }

    /// <summary>
    /// Convenience overload for the common case: a single prefix or postfix
    /// on a method.
    /// </summary>
    /// <param name="kind">Either "prefix" or "postfix" (case-insensitive).</param>
    public static bool PatchSimple(
        HarmonyLib.Harmony harmony,
        string type,
        string method,
        string handler,
        Type   owner,
        string kind  = "postfix",
        string label = "<unlabeled>")
    {
        if (string.Equals(kind, "prefix", StringComparison.OrdinalIgnoreCase))
            return Patch(harmony, type, method, prefix: handler, owner: owner, label: label);
        if (string.Equals(kind, "postfix", StringComparison.OrdinalIgnoreCase))
            return Patch(harmony, type, method, postfix: handler, owner: owner, label: label);
        if (string.Equals(kind, "transpiler", StringComparison.OrdinalIgnoreCase))
            return Patch(harmony, type, method, transpiler: handler, owner: owner, label: label);
        if (string.Equals(kind, "finalizer", StringComparison.OrdinalIgnoreCase))
            return Patch(harmony, type, method, finalizer: handler, owner: owner, label: label);
        CrestDiag.Log(Source, label + ": unknown patch kind '" + kind + "' (expected prefix|postfix|transpiler|finalizer)");
        return false;
    }
}
