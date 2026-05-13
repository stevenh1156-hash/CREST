using HarmonyLib;
using HarmonyLib.BUTR.Extensions;

using System;

namespace Bannerlord.Harmony;

/// <summary>
/// Phase Y.7 -- tier-7+ troop unlocker. Vanilla v1.4.2 caps troops at tier 6
/// via DefaultCharacterStatsModel.MaxCharacterTier returning 6. Many community
/// troop trees go to tier 7 / 8 but those troops can't be upgraded to or
/// auto-recruited as volunteers because the cap blocks them.
///
/// Two postfix patches lift the cap to a configurable max (default 7):
///   * DefaultCharacterStatsModel.get_MaxCharacterTier
///   * DefaultVolunteerModel.get_MaxVolunteerTier
///
/// Master toggle EnableTierUnlocker (default OFF). Cap value read fresh from
/// CrestConfig.GetInt("TierUnlockerMax", 7) on every call.
/// </summary>
internal static class CrestTierUnlocker
{
    private const string Source = nameof(CrestTierUnlocker);
    private static bool _patched;

    public static void TryApply(HarmonyLib.Harmony harmony)
    {
        if (_patched) return;

        if (!CrestConfig.IsEnabled("EnableTierUnlocker", defaultValue: false))
        {
            CrestDiag.Log(Source, "master toggle OFF -- not binding tier-cap patches");
            _patched = true;
            return;
        }

        try
        {
            BindPostfix(harmony,
                "TaleWorlds.CampaignSystem.GameComponents.DefaultCharacterStatsModel",
                "get_MaxCharacterTier", nameof(MaxCharacterTierPostfix), label: "MaxCharacterTier");
            BindPostfix(harmony,
                "TaleWorlds.CampaignSystem.GameComponents.DefaultVolunteerModel",
                "get_MaxVolunteerTier", nameof(MaxVolunteerTierPostfix), label: "MaxVolunteerTier");

            _patched = true;
            CrestDiag.Log(Source, "patched tier caps (gated on EnableTierUnlocker)");
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "TryApply", ex);
        }
    }

    private static void BindPostfix(HarmonyLib.Harmony harmony, string typeName, string methodName,
        string handlerName, string label)
    {
        try
        {
            var t = AccessTools2.TypeByName(typeName);
            if (t == null) { CrestDiag.Log(Source, label + " skipped: type missing"); return; }
            var m = AccessTools2.Method(t, methodName);
            if (m == null) { CrestDiag.Log(Source, label + " skipped: method missing"); return; }
            harmony.Patch(m, postfix: new HarmonyMethod(typeof(CrestTierUnlocker), handlerName));
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, label + " bind", ex); }
    }

    private static void MaxCharacterTierPostfix(ref int __result)
    {
        var max = CrestConfig.GetInt("TierUnlockerMax", 7);
        if (max > __result) __result = max;
    }

    private static void MaxVolunteerTierPostfix(ref int __result)
    {
        var max = CrestConfig.GetInt("TierUnlockerVolunteerMax", 7);
        if (max > __result) __result = max;
    }
}
