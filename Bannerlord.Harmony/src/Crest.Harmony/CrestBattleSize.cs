// CrestBattleSize.cs -- battle-size cap lift + cavalry-aware spawn limiter.
//
// Always-on. Controlled entirely by the in-game Options -> Battle Size
// control. Naval is auto-derived as half of land. Field battles, sieges,
// and sally-outs scale up to the engine's native ~2040 agent ceiling, with
// a per-troop spawn loop that walks the queued roster and stops when the
// agent budget runs out (each cavalry costs 2 agent slots: rider + horse;
// each infantry costs 1).

using HarmonyLib;
using HarmonyLib.BUTR.Extensions;

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Reflection;

using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.AgentOrigins;
using TaleWorlds.CampaignSystem.MapEvents;
using TaleWorlds.CampaignSystem.Roster;
using TaleWorlds.CampaignSystem.TroopSuppliers;
using TaleWorlds.Core;
using TaleWorlds.Localization;
using TaleWorlds.MountAndBlade;

namespace Bannerlord.Harmony;

internal static class CrestBattleSize
{
    private const string Source = nameof(CrestBattleSize);
    private const int MaxAgents = 2040;
    private const int SafeAgentBudget = 2030;
    private const int LargeBattleThreshold = 999;

    // Replacement preset list for the in-game Battle Size control.
    // Vanilla = [200, 300, 400, 500, 600, 800, 1000].
    // The Options UI is hardcoded to 7 entries (one per str_options_type_BattleSize_0..6
    // localization key), so we keep 7 stops but rebalance the range to cover
    // 300-2040 with reasonable granularity. Y.11c: user wants slider-like
    // control over 300-2040; 7 stops at ~300-300-300-300-300-300-240 spacing
    // is the closest we can get without rewriting the gauntlet widget.
    // Labels are stripped to just the number via FindTextPostfix so "Engine
    // Max" / "Very High" / etc. don't appear; users see "300", "600", etc.
    private static readonly int[] Presets = { 300, 600, 900, 1200, 1500, 1800, 2040 };
    private static readonly string[] Labels = { "Very Low", "Low", "Medium", "High", "Very High", "Ultra", "Engine Max" };

    private static bool _patched;

    public static void TryApply(HarmonyLib.Harmony harmony)
    {
        if (_patched) return;
        try
        {
            ReplacePresetArrays();

            BindStatic(harmony, "TaleWorlds.MountAndBlade.BannerlordConfig",            "get_MaxBattleSize",          nameof(MaxBattleSizePostfix), "MaxBattleSize");
            BindStatic(harmony, "TaleWorlds.MountAndBlade.BannerlordConfig",            "GetRealBattleSizeForNaval",  nameof(NavalPostfix),         "Naval");
            BindStatic(harmony, "TaleWorlds.Core.GameTextManager",                      "FindText",                   nameof(FindTextPostfix),      "FindText");

            // 1.4+ exclusive Harmony patches (the cavalry-aware spawn limiter
            // tied to DefaultBattleMissionAgentSpawnLogic + MissionBattleSideSpawnContext)
            // live in the optional Crest.Harmony.Beta.dll. On Beta installs the
            // bridge invokes Beta-side registration here. Public installs skip --
            // they still get preset arrays + max-battle-size cap + FindText cleanup,
            // just not the per-troop spawn budget.
            CrestBetaBridge.RegisterBetaPatches?.Invoke(harmony);

            _patched = true;
            CrestDiag.Log(Source, "patched (always-on; preset count=" + Presets.Length + ", agent cap=" + MaxAgents + ")");
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "TryApply", ex); }
    }

    private static void BindStatic(HarmonyLib.Harmony h, string typeName, string method, string handler, string label)
    {
        try
        {
            var t = AccessTools2.TypeByName(typeName);
            if (t == null) { CrestDiag.Log(Source, label + " skipped: type missing"); return; }
            var m = AccessTools2.Method(t, method);
            if (m == null) { CrestDiag.Log(Source, label + " skipped: method missing"); return; }
            h.Patch(m, postfix: new HarmonyMethod(typeof(CrestBattleSize), handler));
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, label + " bind", ex); }
    }

    // === preset-array replacement (mutates BannerlordConfig at startup) ===

    private static void ReplacePresetArrays()
    {
        var t = AccessTools2.TypeByName("TaleWorlds.MountAndBlade.BannerlordConfig");
        if (t == null) return;
        SetField(t, "_battleSizes",         Presets);
        SetField(t, "_siegeBattleSizes",    Presets);
        SetField(t, "_sallyOutBattleSizes", Presets.Select(x => x / 2).ToArray());
    }

    private static void SetField(Type bcType, string fieldName, int[] values)
    {
        var fld = bcType.GetField(fieldName, BindingFlags.Static | BindingFlags.NonPublic);
        fld?.SetValue(null, values);
    }

    // === postfixes ===

    private static void MaxBattleSizePostfix(ref int __result) => __result = Presets[Presets.Length - 1];

    private static void NavalPostfix(ref int __result)
    {
        int idx = BannerlordConfig.BattleSize;
        if (idx < 0 || idx >= Presets.Length) idx = Presets.Length - 1;
        __result = Presets[idx] / 2;
    }

    // MaxTroopsPostfix moved to Crest.Harmony.Beta.dll (CrestBattleSizeBetaPatches).
    // It patches DefaultBattleMissionAgentSpawnLogic.get_MaxNumberOfTroopsForMission,
    // a 1.4-only TaleWorlds API symbol.

    private static void FindTextPostfix(ref TextObject __result, string id, string variation = null)
    {
        try
        {
            const string root = "str_options_type_BattleSize_";
            if (id == null || !id.StartsWith(root)) return;
            // Y.22c: just the number, no descriptive label. The labels
            // ("Very Low" / "Medium" / "Engine Max") add visual noise without
            // helping anyone -- anyone tweaking battle size is doing it by
            // raw count, not by the label's name. Display "200" instead of
            // "Very Low (200)".
            for (int i = 0; i < Presets.Length; i++)
                if (id == root + i) { __result = new TextObject(Presets[i].ToString(CultureInfo.InvariantCulture)); return; }
        }
        catch { /* swallow -- text fallback is acceptable */ }
    }

    // === cavalry-aware Init postfix ===
    // Lives in Crest.Harmony.Beta.dll (CrestBattleSizeBetaPatches class).
    // It depends on 1.4-only TaleWorlds API (DefaultBattleMissionAgentSpawnLogic,
    // MissionBattleSideSpawnContext). On Beta installs CrestBetaBridge loads
    // the Beta DLL and registers those Harmony patches alongside the always-safe
    // patches above. On Public installs (e1.3.x) the spawn limiter is absent;
    // preset arrays + MaxBattleSize cap + FindText cleanup still apply.

#if NEVER_DEFINED_LEFT_FOR_GIT_HISTORY
    private static readonly Type _spawnLogicType = AccessTools2.TypeByName("TaleWorlds.MountAndBlade.DefaultBattleMissionAgentSpawnLogic");
    private static readonly FieldInfo _battleSideContextsField = _spawnLogicType?.GetField("_battleSideSpawnContexts", BindingFlags.Instance | BindingFlags.NonPublic);
    private static readonly FieldInfo _phasesField             = _spawnLogicType?.GetField("_phases",                  BindingFlags.Instance | BindingFlags.NonPublic);
    private static readonly FieldInfo _supplierField           = typeof(MissionBattleSideSpawnContext).GetField("_troopSupplier", BindingFlags.Instance | BindingFlags.NonPublic);

    private static void InitPostfix(DefaultBattleMissionAgentSpawnLogic __instance,
        bool spawnDefenders, bool spawnAttackers,
        in MissionSpawnSettings reinforcementSpawnSettings)
    {
        try
        {
            if (_battleSideContextsField == null || _phasesField == null) return;
            var contexts = (MissionBattleSideSpawnContext[])_battleSideContextsField.GetValue(__instance);
            var phases   = (List<MissionSpawnPhase>[])     _phasesField.GetValue(__instance);
            if (phases == null || phases.Length < 2) return;

            int currentTotal = 0;
            for (int s = 0; s < 2; s++)
                if (phases[s] != null) foreach (var p in phases[s]) currentTotal += p.InitialSpawnNumber;
            if (currentTotal <= LargeBattleThreshold) return;

            var queues = BuildQueues(contexts);
            int[] desired = { 0, 0 };
            for (int s = 0; s < 2; s++)
                foreach (var p in phases[s]) desired[s] += p.InitialSpawnNumber;

            int higher = desired[0] >= desired[1] ? 0 : 1;
            int lower  = 1 - higher;
            int[] customSizes = (int[])desired.Clone();
            float origRatio = desired[higher] > 0 ? (float)desired[lower] / desired[higher] : 0f;
            int[] safe = { 0, 0 };
            int budget = SafeAgentBudget;

            while (budget > 1
                   && ((queues[higher].Count > 0 && customSizes[higher] > 0)
                    || (queues[lower].Count  > 0 && customSizes[lower]  > 0)))
            {
                for (int s = 0; s < 2 && budget > 1; s++)
                {
                    if (s == lower && safe[higher] > 0)
                    {
                        if ((float)safe[lower] / safe[higher] >= origRatio) continue;
                    }
                    if (queues[s].Count == 0 || customSizes[s] <= 0) continue;

                    int cost = (!contexts[s].SpawnWithHorses
                               || queues[s].Peek().Troop.Equipment.Horse.IsEmpty) ? 1 : 2;
                    if (cost > budget) break;

                    budget -= cost;
                    safe[s]++;
                    queues[s].Dequeue();
                    customSizes[s]--;
                }
            }

            DiagOnce("BattleSize.Allocated",
                "InitPostfix: vanilla=" + currentTotal + " -> safe=" + (safe[0] + safe[1]) +
                " (def=" + safe[0] + ", atk=" + safe[1] + ")");

            for (int s = 0; s < 2; s++)
            {
                int rem = safe[s];
                foreach (var p in phases[s])
                {
                    int newInit = Math.Min(p.InitialSpawnNumber, rem);
                    int diff = p.InitialSpawnNumber - newInit;
                    if (diff > 0) { p.InitialSpawnNumber = newInit; p.RemainingSpawnNumber += diff; }
                    rem -= newInit;
                }
            }

            var dp = phases[0].FirstOrDefault();
            var ap = phases[1].FirstOrDefault();
            if (dp != null && ap != null)
                __instance.Mission.SetBattleAgentCount(Math.Min(dp.InitialSpawnNumber, ap.InitialSpawnNumber));
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "InitPostfix", ex); }
    }

    private static Queue<IAgentOriginBase>[] BuildQueues(MissionBattleSideSpawnContext[] sides)
    {
        var q = new Queue<IAgentOriginBase>[2];
        bool isCampaign = Game.Current?.GameType is Campaign;
        for (int s = 0; s < 2; s++)
        {
            q[s] = new Queue<IAgentOriginBase>();
            try
            {
                var supplier = _supplierField?.GetValue(sides[s]);
                if (supplier == null) continue;
                IEnumerable<IAgentOriginBase> origins;
                if (isCampaign && supplier is PartyGroupTroopSupplier pgts) origins = CampaignTroops(pgts);
                else if (supplier is CustomBattleTroopSupplier cbts)        origins = CustomTroops(cbts);
                else if (supplier is IMissionTroopSupplier its)             origins = its.GetAllTroops();
                else continue;
                foreach (var o in origins) q[s].Enqueue(o);
            }
            catch (Exception ex) { CrestDiag.LogCaught(Source, "BuildQueues s=" + s, ex); }
        }
        return q;
    }

#endif // NEVER_DEFINED_LEFT_FOR_GIT_HISTORY

    // Helpers for the (now-removed) cavalry-aware spawn limiter were
    // kept here originally; they've been ported to Crest.Harmony.Beta.dll
    // (CrestBattleSizeBetaPatches.cs) as a self-contained class. The
    // _diag dictionary below is kept because DiagOnce is still referenced
    // by the always-safe code paths above (preset arrays, etc).

    private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, byte> _diag = new();
    private static void DiagOnce(string k, string m) { if (_diag.TryAdd(k, 0)) CrestDiag.Log(Source, m); }
}
