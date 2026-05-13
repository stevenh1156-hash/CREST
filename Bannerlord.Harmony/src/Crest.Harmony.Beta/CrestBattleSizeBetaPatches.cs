using HarmonyLib;
using HarmonyLib.BUTR.Extensions;

using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;

using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.AgentOrigins;
using TaleWorlds.CampaignSystem.MapEvents;
using TaleWorlds.CampaignSystem.Roster;
using TaleWorlds.CampaignSystem.TroopSuppliers;
using TaleWorlds.Core;
using TaleWorlds.MountAndBlade;

using Bannerlord.Harmony;  // CrestDiag

namespace Bannerlord.Harmony.Beta;

/// <summary>
/// Cavalry-aware spawn limiter that lifts Bannerlord's hard-coded battle
/// agent budget. The corresponding TaleWorlds APIs
/// (DefaultBattleMissionAgentSpawnLogic, MissionBattleSideSpawnContext)
/// only exist on e1.4.x and later, so this class lives in
/// Crest.Harmony.Beta.dll and is loaded only when the running game's
/// Native module reports v1.4.0 or higher.
///
/// The Public Crest.Harmony.dll's CrestBattleSize.TryApply still binds
/// the always-safe parts (preset arrays, MaxBattleSize cap, FindText
/// label cleanup) on every install. This class registers the additional
/// 1.4-only postfixes (MaxTroops + Init).
///
/// Code copied verbatim from the pre-Option-B CrestBattleSize.cs --
/// kept in a distinct class+namespace to avoid type collision with
/// the main DLL's CrestBattleSize.
/// </summary>
internal static class CrestBattleSizeBetaPatches
{
    private const string Source = "CrestBattleSizeBetaPatches";
    private const int MaxAgents = 2040;
    private const int SafeAgentBudget = 2030;
    private const int LargeBattleThreshold = 999;

    private static bool _registered;

    public static void Register(HarmonyLib.Harmony harmony)
    {
        if (_registered) return;
        try
        {
            // Beta-safe binds: verify signature before patching so a
            // beta-branch TaleWorlds-API drift logs and skips instead of
            // triggering a native fault when Harmony invokes a postfix
            // bound to a method whose shape changed underneath us. The
            // Options menu / battle-size dropdown reads MaxNumberOfTroopsForMission
            // and a mismatched delegate there crashes below the BUTR
            // exception interceptor's reach (rgl_log + BEW unwritten).
            BindStatic(harmony, "TaleWorlds.MountAndBlade.DefaultBattleMissionAgentSpawnLogic", "get_MaxNumberOfTroopsForMission", nameof(MaxTroopsPostfix), "MaxTroops",
                expectedReturnType: typeof(int), expectedParamCount: 0);
            BindStatic(harmony, "TaleWorlds.MountAndBlade.DefaultBattleMissionAgentSpawnLogic", "Init",                            nameof(InitPostfix),      "Init",
                expectedReturnType: typeof(void), expectedParamCount: 3);
            _registered = true;
            CrestDiag.Log(Source, "registered (Beta-only spawn limiter active; agent cap=" + MaxAgents + ")");
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "Register", ex); }
    }

    private static void BindStatic(HarmonyLib.Harmony h, string typeName, string method, string handler, string label,
        Type? expectedReturnType = null, int? expectedParamCount = null)
    {
        try
        {
            var t = AccessTools2.TypeByName(typeName);
            if (t == null) { CrestDiag.Log(Source, label + " skipped: type missing"); return; }
            var m = AccessTools2.Method(t, method);
            if (m == null) { CrestDiag.Log(Source, label + " skipped: method missing"); return; }

            // Pre-bind signature verification. Harmony.Patch will accept a
            // method whose params/return type don't match what our postfix
            // expects, then the IL it generates around the patched call
            // pushes the wrong shape into our postfix's stack frame -> CTD
            // with no managed exception (BUTR finalizer can't catch it).
            if (expectedReturnType != null && m.ReturnType != expectedReturnType)
            {
                CrestDiag.Log(Source, label + " skipped: return type mismatch (got "
                    + m.ReturnType.FullName + ", expected " + expectedReturnType.FullName + ")");
                return;
            }
            if (expectedParamCount != null && m.GetParameters().Length != expectedParamCount.Value)
            {
                CrestDiag.Log(Source, label + " skipped: param count mismatch (got "
                    + m.GetParameters().Length + ", expected " + expectedParamCount.Value + ")");
                return;
            }

            h.Patch(m, postfix: new HarmonyMethod(typeof(CrestBattleSizeBetaPatches), handler));
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, label + " bind", ex); }
    }

    private static void MaxTroopsPostfix(ref int __result)
    {
        try
        {
            if (__result > LargeBattleThreshold) __result = MaxAgents;
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "MaxTroopsPostfix", ex); }
    }

    private static readonly Type? _spawnLogicType = AccessTools2.TypeByName("TaleWorlds.MountAndBlade.DefaultBattleMissionAgentSpawnLogic");
    private static readonly FieldInfo? _battleSideContextsField = _spawnLogicType?.GetField("_battleSideSpawnContexts", BindingFlags.Instance | BindingFlags.NonPublic);
    private static readonly FieldInfo? _phasesField             = _spawnLogicType?.GetField("_phases",                  BindingFlags.Instance | BindingFlags.NonPublic);
    private static readonly FieldInfo? _supplierField           = typeof(MissionBattleSideSpawnContext).GetField("_troopSupplier", BindingFlags.Instance | BindingFlags.NonPublic);

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

    private static IEnumerable<IAgentOriginBase> CampaignTroops(PartyGroupTroopSupplier supplier)
    {
        var partyGroup = (MapEventSide)AccessTools2.Property(typeof(PartyGroupTroopSupplier), "PartyGroup").GetValue(supplier);
        var readyList = (List<ValueTuple<FlattenedTroopRosterElement, MapEventParty, float>>)
            AccessTools2.Field(typeof(MapEventSide), "_readyTroopsPriorityList").GetValue(partyGroup);
        var ordered = readyList.OrderByDescending(x => x.Item3).ToList();
        var ctor = AccessTools2.Constructor(typeof(PartyGroupAgentOrigin),
            new[] { typeof(PartyGroupTroopSupplier), typeof(UniqueTroopDescriptor), typeof(int) });
        var arr = new PartyGroupAgentOrigin[ordered.Count];
        for (int i = 0; i < arr.Length; i++)
            arr[i] = (PartyGroupAgentOrigin)ctor.Invoke(new object[] { supplier, ordered[i].Item1.Descriptor, i });
        return arr;
    }

    private static IEnumerable<IAgentOriginBase> CustomTroops(CustomBattleTroopSupplier supplier)
    {
        var combatant = (CustomBattleCombatant)AccessTools2.Field(typeof(CustomBattleTroopSupplier), "_customBattleCombatant").GetValue(supplier);
        var isPlayer  = (bool)                  AccessTools2.Field(typeof(CustomBattleTroopSupplier), "_isPlayerSide").GetValue(supplier);
        var origQ     = (TaleWorlds.Library.PriorityQueue<float, BasicCharacterObject>)
            AccessTools2.Field(typeof(CustomBattleTroopSupplier), "_characters").GetValue(supplier);
        var copy      = new TaleWorlds.Library.PriorityQueue<float, BasicCharacterObject>(origQ);
        var list      = new List<BasicCharacterObject>();
        while (copy.Count > 0) list.Add(copy.DequeueValue());
        var arr = new CustomBattleAgentOrigin[list.Count];
        for (int i = 0; i < arr.Length; i++)
            arr[i] = new CustomBattleAgentOrigin(combatant, list[i], supplier, isPlayer, i, new UniqueTroopDescriptor(NextSeed()));
        return arr;
    }

    private static int _nextSeed;
    private static int NextSeed()
    {
        if (_nextSeed == 0) _nextSeed = Game.Current.NextUniqueTroopSeed;
        return _nextSeed++;
    }

    private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, byte> _diag = new();
    private static void DiagOnce(string k, string m) { if (_diag.TryAdd(k, 0)) CrestDiag.Log(Source, m); }
}
