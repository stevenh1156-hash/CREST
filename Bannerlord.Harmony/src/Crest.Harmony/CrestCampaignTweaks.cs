using HarmonyLib;
using HarmonyLib.BUTR.Extensions;

using System;
using System.Collections.Concurrent;
using System.Reflection;

namespace Bannerlord.Harmony;

/// <summary>
/// Phase Y.5 / Y.5b -- a curated bundle of small Harmony-patch QoL tweaks
/// for the campaign layer. Master toggle EnableCampaignTweaks (default OFF)
/// gates everything; each individual feature has its own opt-in toggle.
///
/// Features (each loosely-typed via reflection so a missing TaleWorlds type
/// just disables that one tweak instead of crashing the module):
///
///   * PreventClanDeath            -- AgingCampaignBehavior.IsItTimeOfDeath
///   * PlayerNoFlinch              -- Mission.RegisterBlow (player team)
///   * NoExecutionPenalty          -- CharacterRelationCampaignBehavior.OnHeroKilled
///   * ClanTournamentExclusion     -- FightTournamentGame.CanBeAParticipant
///   * ClanPartySpeedBonus         -- MobileParty.CalculateSpeed (postfix)
///   * FasterShips                 -- MobileParty.CalculateSpeed (postfix, IsCurrentlyAtSea-gated)
///   * StopPrisonerEscape          -- PrisonerReleaseCampaignBehavior daily/hourly ticks
///   * LootCapturedHeroes          -- MapEvent.LootCasualtyCharacter
///   * NoArrowsStuck               -- Mission.HandleMissileCollisionReaction (no porcupine)
///   * MarriageStaysInClan         -- DefaultMarriageModel.GetClanAfterMarriage
///   * PregnancyChanceUncapped     -- DefaultPregnancyModel.GetDailyChanceOfPregnancyForHero
///   * UnlockAllSmithingRecipes    -- CraftingCampaignBehavior.IsOpened
///
/// All gates re-read CrestConfig fresh per call; mtime cache makes that cheap.
/// </summary>
internal static class CrestCampaignTweaks
{
    private const string Source = nameof(CrestCampaignTweaks);
    private static bool _patched;

    public static void TryApply(HarmonyLib.Harmony harmony)
    {
        if (_patched) return;
        _patched = true;

        // Y.12b-fix4: standalone-feature patches that have their own MCM
        // toggles MUST be bound regardless of the legacy EnableCampaignTweaks
        // master gate. Each postfix re-checks its own toggle at runtime so
        // they're safe to always-bind. Without this split, a user who only
        // wants Battle Convergence (or Faster Ships, or the achievements
        // unblocker, etc.) but doesn't enable the master Campaign Tweaks
        // toggle gets nothing -- because the BindPatch chain never executes.
        try
        {
            // Y.12c: Battle Convergence is now a MissionBehavior (CrestBattleConvergence.cs)
            // hooked from SubModule.OnMissionBehaviorInitialize, NOT a Harmony patch.
            // The Y.12b CheckNearbyPartiesToJoinPlayerMapEvent postfix has been deleted --
            // it patched the wrong layer (campaign-map join, not in-mission reinforcements).
            //
            // Y.12d-fix21: the legacy Y.12 wave-size scaler (SpawnSettingsPostfix) is no
            // longer bound. It silently multiplied vanilla's ReinforcementBatchPercentage,
            // overriding whatever the user picked in the standard Bannerlord Options
            // → Battles menu. Battle Convergence (real lords joining mid-battle) is the
            // proper "more troops" feature; the wave scaler was redundant and disruptive.
            // SpawnSettingsPostfix and the EnableReinforcements / ReinforcementWaveMultiplier
            // / ReinforcementIntervalSec / ReinforcementMaxWaves config keys are kept
            // dead-code-style for backward compat with old crest.json files; they no
            // longer do anything at runtime.

            BindPatch(harmony, "TaleWorlds.CampaignSystem.Party.MobileParty",
                "CalculateSpeed", nameof(FasterShipsPostfix), prefix: false, label: "FasterShips");

            BindPatch(harmony, "SandBox.CampaignBehaviors.DumpIntegrityCampaignBehavior",
                "IsGameIntegrityAchieved", nameof(GameIntegrityPostfix), prefix: false, label: "AchievementsWithMods");

            // Y.20-fix3: also patch DeactivateAchievements directly. The Y.20-rewrite
            // postfix on IsGameIntegrityAchieved only blocks the cheat-detection
            // path. But AchievementsCampaignBehavior persists _deactivateAchievements
            // via SyncData -- once a save has the flag baked in, it triggers the
            // "{=Z9mcDuDi}Achievements are disabled!" popup on every campaign
            // load without going through IsGameIntegrityAchieved. Prefix returning
            // false skips the entire DeactivateAchievements body, including the
            // popup and the field write.
            BindPatch(harmony, "StoryMode.GameComponents.CampaignBehaviors.AchievementsCampaignBehavior",
                "DeactivateAchievements", nameof(DeactivateAchievementsPrefix), prefix: true, label: "AchievementsDeactivateBlock");

            BindPatch(harmony, "RTSCamera.Patch.Naval.Patch_AgentNavalComponent",
                "Prefix_OnTick", nameof(RTSCameraNavalNoOpPrefix), prefix: true, label: "RTSCameraNavalShim");
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "TryApply standalone", ex); }

        // Legacy "Campaign Tweaks" master gate. The features below are the
        // original cluster (PreventClanDeath, NoFlinch, prisoner escape,
        // marriage, pregnancy, smithing, lifelong learning, etc.) -- they
        // share a single MCM master toggle and bind together for historical
        // reasons. Standalone features above don't go through this gate.
        if (!CrestConfig.IsEnabled("EnableCampaignTweaks", defaultValue: false))
        {
            CrestDiag.Log(Source, "EnableCampaignTweaks OFF -- legacy tweaks not bound (standalone features still active)");
            return;
        }

        try
        {
            BindPatch(harmony, "TaleWorlds.CampaignSystem.CampaignBehaviors.AgingCampaignBehavior",
                "IsItTimeOfDeath", nameof(PreventClanDeathPrefix), prefix: true, label: "PreventClanDeath");

            BindPatch(harmony, "TaleWorlds.MountAndBlade.Mission",
                "RegisterBlow", nameof(NoFlinchPrefix), prefix: true, label: "PlayerNoFlinch");

            BindPatch(harmony, "TaleWorlds.CampaignSystem.CampaignBehaviors.CharacterRelationCampaignBehavior",
                "OnHeroKilled", nameof(NoExecutionPenaltyPrefix), prefix: true, label: "NoExecutionPenalty");

            BindPatch(harmony, "TaleWorlds.CampaignSystem.TournamentGames.FightTournamentGame",
                "CanBeAParticipant", nameof(TournamentExclusionPrefix), prefix: true, label: "ClanTournamentExclusion");

            BindPatch(harmony, "TaleWorlds.CampaignSystem.Party.MobileParty",
                "CalculateSpeed", nameof(ClanSpeedBonusPostfix), prefix: false, label: "ClanPartySpeedBonus");

            // Phase Y.23: Faster Ships -- now bound unconditionally above (Y.12b-fix4).

            // Y.5b additions:
            BindPatch(harmony, "TaleWorlds.CampaignSystem.CampaignBehaviors.PrisonerReleaseCampaignBehavior",
                "DailyHeroTick", nameof(StopPrisonerEscapeDailyPrefix), prefix: true, label: "StopPrisonerEscape (daily)");
            BindPatch(harmony, "TaleWorlds.CampaignSystem.CampaignBehaviors.PrisonerReleaseCampaignBehavior",
                "HourlyPartyTick", nameof(StopPrisonerEscapeHourlyPrefix), prefix: true, label: "StopPrisonerEscape (hourly)");

            BindPatch(harmony, "TaleWorlds.CampaignSystem.MapEvents.MapEvent",
                "LootDefeatedPartyPrisoners", nameof(LootCapturedHeroesPostfix), prefix: false, label: "LootCapturedHeroes");

            BindPatch(harmony, "TaleWorlds.MountAndBlade.Mission",
                "HandleMissileCollisionReaction", nameof(NoArrowsStuckPostfix), prefix: false, label: "NoArrowsStuck");

            BindPatch(harmony, "TaleWorlds.CampaignSystem.GameComponents.DefaultMarriageModel",
                "GetClanAfterMarriage", nameof(MarriageStaysInClanPostfix), prefix: false, label: "MarriageStaysInClan");

            BindPatch(harmony, "TaleWorlds.CampaignSystem.GameComponents.DefaultPregnancyModel",
                "GetDailyChanceOfPregnancyForHero", nameof(PregnancyChanceUncappedPostfix), prefix: false, label: "PregnancyChanceUncapped");

            BindPatch(harmony, "TaleWorlds.CampaignSystem.CampaignBehaviors.CraftingCampaignBehavior",
                "IsOpened", nameof(UnlockAllSmithingRecipesPostfix), prefix: false, label: "UnlockAllSmithingRecipes");

            // Phase Y.19: Lifelong Learning -- never let learning rate go below
            // a configurable floor (default 0.5 = 50% of max). Mirrors the
            // upstream model-swap approach via a postfix on the default model.
            BindPatch(harmony, "TaleWorlds.CampaignSystem.GameComponents.DefaultCharacterDevelopmentModel",
                "CalculateLearningRate", nameof(LifelongLearningPostfix), prefix: false, label: "LifelongLearning");

            // Y.12b-fix4: BattleConvergence, Reinforcements, RTSCameraNavalShim,
            // and AchievementsWithMods are now bound unconditionally above.
            // They each have their own MCM toggle and runtime guard, so they
            // stay independent of the EnableCampaignTweaks master.

            // Phase Y.21: Tavern companion multiplier. CompanionsCampaignBehavior
            // calls TrySpawnNewCompanion once per daily tick; the spawn is gated
            // by an _aliveCount >= _desiredTotalCompanionCount cap. Two patches:
            //   * DailyTick postfix: call TrySpawnNewCompanion (mult-1) more times.
            //   * _desiredTotalCompanionCount postfix: multiply the cap so daily
            //     spawns aren't immediately blocked when the world fills up.
            BindPatch(harmony, "TaleWorlds.CampaignSystem.CampaignBehaviors.CompanionsCampaignBehavior",
                "DailyTick", nameof(CompanionDailyTickPostfix), prefix: false, label: "TavernCompanions.DailyTick");
            BindPatch(harmony, "TaleWorlds.CampaignSystem.CampaignBehaviors.CompanionsCampaignBehavior",
                "get__desiredTotalCompanionCount", nameof(DesiredCompanionCountPostfix), prefix: false, label: "TavernCompanions.DesiredCount");

            // Phase Y.11: battle-size handling lives in CrestBattleSize (loaded
            // from SubModule). Always-on; no per-feature toggle here.

            // Player-team health regen runs as a per-tick logic check inside
            // MissionBehavior, no Harmony patch needed -- handled in
            // CrestCampaignTweaksMissionLogic.OnMissionTick. Add it as a
            // mission behavior in CrestCompanionHotswap-style hook.

            CrestDiag.Log(Source, "patched campaign tweaks (legacy EnableCampaignTweaks group)");
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "TryApply legacy", ex);
        }
    }

    private static void BindPatch(HarmonyLib.Harmony harmony, string typeName, string methodName,
        string handlerName, bool prefix, string label)
    {
        try
        {
            var t = AccessTools2.TypeByName(typeName);
            if (t == null) { CrestDiag.Log(Source, label + " skipped: type missing (" + typeName + ")"); return; }
            var m = AccessTools2.Method(t, methodName);
            if (m == null) { CrestDiag.Log(Source, label + " skipped: method missing (" + typeName + "." + methodName + ")"); return; }
            var hm = new HarmonyMethod(typeof(CrestCampaignTweaks), handlerName);
            if (prefix) harmony.Patch(m, prefix: hm);
            else harmony.Patch(m, postfix: hm);
            // Y.12b-fix4: explicit success log so future bind-vs-fire confusion
            // is one grep away from being resolved.
            CrestDiag.Log(Source, label + " bound: " + typeName + "." + methodName + " (" + (prefix ? "prefix" : "postfix") + ")");
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, label + " bind", ex); }
    }

    private static void BindCtorPatch(HarmonyLib.Harmony harmony, string typeName, string[] paramTypeNames,
        string handlerName, bool prefix, string label)
    {
        try
        {
            var t = AccessTools2.TypeByName(typeName);
            if (t == null) { CrestDiag.Log(Source, label + " skipped: type missing"); return; }

            // Resolve param types by name, allowing T[] suffix for arrays
            // and T+N for nested types (handled by Type.GetType + assembly scan).
            var pts = new Type[paramTypeNames.Length];
            for (int i = 0; i < paramTypeNames.Length; i++)
            {
                var name = paramTypeNames[i];
                bool isArray = name.EndsWith("[]");
                var elemName = isArray ? name.Substring(0, name.Length - 2) : name;
                Type elemType = null;
                // Nested types have '+' in the name. AccessTools2.TypeByName
                // may not resolve them, so split and use Type.GetNestedType.
                if (elemName.Contains("+"))
                {
                    var split = elemName.IndexOf('+');
                    var outerName = elemName.Substring(0, split);
                    var innerName = elemName.Substring(split + 1);
                    var outer = AccessTools2.TypeByName(outerName);
                    if (outer != null)
                    {
                        elemType = outer.GetNestedType(innerName, BindingFlags.Public | BindingFlags.NonPublic);
                    }
                }
                else
                {
                    elemType = AccessTools2.TypeByName(elemName);
                }
                if (elemType == null) { CrestDiag.Log(Source, label + " skipped: param type " + elemName + " missing"); return; }
                pts[i] = isArray ? elemType.MakeArrayType() : elemType;
            }

            var ctor = t.GetConstructor(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic, null, pts, null);
            if (ctor == null) { CrestDiag.Log(Source, label + " skipped: ctor missing"); return; }

            var hm = new HarmonyMethod(typeof(CrestCampaignTweaks), handlerName);
            if (prefix) harmony.Patch(ctor, prefix: hm);
            else harmony.Patch(ctor, postfix: hm);
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, label + " ctor bind", ex); }
    }

    // ===== handlers =====

    private static bool PreventClanDeathPrefix(object hero)
    {
        try
        {
            if (!CrestConfig.IsEnabled("PreventClanDeath", defaultValue: false)) return true;
            var t = hero?.GetType();
            var clan = t?.GetProperty("Clan")?.GetValue(hero);
            var alive = (bool)(t?.GetProperty("IsAlive")?.GetValue(hero) ?? false);
            if (clan == null || !alive) return true;
            if (CrestConfig.IsEnabled("PreventClanDeathPlayerOnly", defaultValue: false))
            {
                var pc = clan.GetType().GetProperty("PlayerClan", BindingFlags.Public | BindingFlags.Static)?.GetValue(null);
                if (clan != pc) return true;
            }
            return false;
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "PreventClanDeath", ex); return true; }
    }

    private static void NoFlinchPrefix(object victim)
    {
        try
        {
            if (!CrestConfig.IsEnabled("PlayerNoFlinch", defaultValue: false)) return;
            if (victim == null) return;
            var vt = victim.GetType();
            if (!(bool)(vt.GetProperty("IsHuman")?.GetValue(victim) ?? false)) return;
            var team = vt.GetProperty("Team")?.GetValue(victim);
            if (team == null) return;
            if (!(bool)(team.GetType().GetProperty("IsPlayerTeam")?.GetValue(team) ?? false)) return;
            DiagOnce(Source + ".NoFlinch",
                "PlayerNoFlinch loose-typed prefix -- ref Blow not patchable without hard type ref. Feature inert.");
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "PlayerNoFlinch", ex); }
    }

    private static bool NoExecutionPenaltyPrefix(object victim, object killer, object detail)
    {
        try
        {
            if (!CrestConfig.IsEnabled("NoExecutionPenalty", defaultValue: false)) return true;
            if (killer == null) return true;
            var mainHero = killer.GetType().GetProperty("MainHero", BindingFlags.Public | BindingFlags.Static)?.GetValue(null);
            if (mainHero == null || !ReferenceEquals(killer, mainHero)) return true;
            int d = Convert.ToInt32(detail);
            return d != 6 && d != 7; // 6=Executed, 7=ExecutedByCharacter
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "NoExecutionPenalty", ex); return true; }
    }

    private static bool TournamentExclusionPrefix(object character, bool considerSkills, ref bool __result)
    {
        try
        {
            if (!CrestConfig.IsEnabled("ClanTournamentExclusion", defaultValue: false)) return true;
            if (character == null) return true;
            var ct = character.GetType();
            if (!(bool)(ct.GetProperty("IsHero")?.GetValue(character) ?? false)) return true;
            if ((bool)(ct.GetProperty("IsPlayerCharacter")?.GetValue(character) ?? false)) return true;
            var hero = ct.GetProperty("HeroObject")?.GetValue(character);
            if (hero == null) return true;
            var clan = hero.GetType().GetProperty("Clan")?.GetValue(hero);
            if (clan == null) return true;
            var pc = clan.GetType().GetProperty("PlayerClan", BindingFlags.Public | BindingFlags.Static)?.GetValue(null);
            if (clan == pc) { __result = false; return false; }
            return true;
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "ClanTournamentExclusion", ex); return true; }
    }

    // Phase Z.4: per-Type reflection caches for ClanSpeedBonusPostfix. The
    // postfix runs on every MobileParty.CalculateSpeed call (i.e., for every
    // party on the map every speed recalc) so we have to keep it allocation-
    // and lookup-free in the hot path. Same shape as GetIsAtSeaProp below.
    private static readonly ConcurrentDictionary<Type, PropertyInfo?> _actualClanPropCache    = new();
    private static readonly ConcurrentDictionary<Type, PropertyInfo?> _playerClanStaticCache = new();
    private static PropertyInfo? GetActualClanProp(Type t)
    {
        return _actualClanPropCache.GetOrAdd(t, type =>
        {
            try { return type.GetProperty("ActualClan"); }
            catch { return null; }
        });
    }
    private static PropertyInfo? GetPlayerClanStaticProp(Type clanType)
    {
        return _playerClanStaticCache.GetOrAdd(clanType, type =>
        {
            try { return type.GetProperty("PlayerClan", BindingFlags.Public | BindingFlags.Static); }
            catch { return null; }
        });
    }

    private static void ClanSpeedBonusPostfix(object __instance, ref float __result)
    {
        try
        {
            var bonus = CrestConfig.GetFloat("ClanPartySpeedBonus", 0f);
            if (bonus <= 0f) return; // master gate (feature disabled when 0)
            if (__instance == null) return;
            var clanProp = GetActualClanProp(__instance.GetType());
            if (clanProp == null) return;
            var clan = clanProp.GetValue(__instance);
            if (clan == null) return;
            var playerClanProp = GetPlayerClanStaticProp(clan.GetType());
            if (playerClanProp == null) return;
            var pc = playerClanProp.GetValue(null);
            if (clan != pc) return;
            __result += bonus;
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "ClanPartySpeedBonus", ex); }
    }

    // Phase Y.23: Faster Ships. Cache the IsCurrentlyAtSea reflection lookup
    // so the postfix can run cheaply on every MobileParty.CalculateSpeed call.
    // ConcurrentDictionary indexed by Type guards against rare race conditions
    // and tolerates the property being missing on older saves / non-NavalDLC
    // worlds (returns null PropertyInfo, which the postfix treats as "not at sea").
    private static readonly ConcurrentDictionary<Type, PropertyInfo?> _isAtSeaPropCache = new();
    private static PropertyInfo? GetIsAtSeaProp(Type t)
    {
        return _isAtSeaPropCache.GetOrAdd(t, type =>
        {
            try { return type.GetProperty("IsCurrentlyAtSea", BindingFlags.Public | BindingFlags.Instance); }
            catch { return null; }
        });
    }

    private static void FasterShipsPostfix(object __instance, ref float __result)
    {
        try
        {
            // Master gate AND the dedicated FasterShips toggle must both be on.
            // (EnableCampaignTweaks already gates BindPatch, but checking again
            //  is cheap and lets users flip FasterShips at runtime without
            //  toggling the entire campaign-tweaks group off.)
            if (!CrestConfig.IsEnabled("EnableFasterShips", defaultValue: false)) return;

            var mult = CrestConfig.GetFloat("FasterShipsMultiplier", 2.0f);
            // Sanity-clamp: <=1 would slow ships, > 8 would teleport them across
            // the map; CrestSettings clamps to 1.0..4.0 already, but guard here
            // in case a user hand-edits crest.json to something nonsensical.
            if (mult <= 1.0f) return;
            if (mult > 8.0f) mult = 8.0f;

            if (__instance == null) return;
            var prop = GetIsAtSeaProp(__instance.GetType());
            if (prop == null) return; // NavalDLC missing or older game version
            var atSea = prop.GetValue(__instance) as bool?;
            if (atSea != true) return;

            __result *= mult;
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "FasterShips", ex); }
    }

    // ===== Y.5b additions =====

    private static bool StopPrisonerEscapeDailyPrefix() =>
        !CrestConfig.IsEnabled("StopPrisonerEscape", defaultValue: false);

    private static bool StopPrisonerEscapeHourlyPrefix() =>
        !CrestConfig.IsEnabled("StopPrisonerEscape", defaultValue: false);

    // Phase Y.5c LootCapturedHeroes: postfix on MapEvent.LootDefeatedPartyPrisoners.
    // For every hero that's now in the PLAYER party's PrisonRoster (and we
    // haven't already looted on a previous battle), copy their battle
    // equipment into the player's loot roster. We track already-looted heroes
    // by reference to avoid duplicating gear if the hero stays prisoner
    // through multiple battles.
    private static readonly System.Collections.Generic.HashSet<TaleWorlds.CampaignSystem.Hero> _alreadyLootedHeroes = new();

    private static void LootCapturedHeroesPostfix(
        TaleWorlds.Library.MBReadOnlyList<TaleWorlds.CampaignSystem.MapEvents.MapEventParty> winnerParties,
        TaleWorlds.Library.MBReadOnlyList<TaleWorlds.CampaignSystem.MapEvents.MapEventParty> defeatedParties)
    {
        try
        {
            if (!CrestConfig.IsEnabled("LootCapturedHeroes", defaultValue: false)) return;
            if (winnerParties == null) return;
            var mainParty = TaleWorlds.CampaignSystem.Party.MobileParty.MainParty;
            foreach (var winner in winnerParties)
            {
                if (winner?.Party?.MobileParty != mainParty) continue; // player only
                if (winner.RosterToReceiveLootItems == null) continue;
                var roster = winner.Party.PrisonRoster?.GetTroopRoster();
                if (roster == null) continue;
                foreach (var element in roster)
                {
                    var character = element.Character;
                    if (character == null || !character.IsHero) continue;
                    var hero = character.HeroObject;
                    if (hero == null) continue;
                    if (!_alreadyLootedHeroes.Add(hero)) continue;
                    var eq = hero.BattleEquipment;
                    if (eq == null) continue;
                    for (int slot = 0; slot < (int)TaleWorlds.Core.EquipmentIndex.NumAllWeaponSlots; slot++)
                    {
                        var item = eq[(TaleWorlds.Core.EquipmentIndex)slot];
                        if (item.IsEmpty) continue;
                        winner.RosterToReceiveLootItems.Add(new TaleWorlds.Core.ItemRosterElement(item, 1));
                    }
                }
            }
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "LootCapturedHeroes", ex); }
    }

    // Phase Y.5c NoArrowsStuck: postfix on Mission.HandleMissileCollisionReaction.
    // When a missile attaches to an agent, immediately delete the just-attached
    // weapon so dead bodies don't accumulate the porcupine effect.
    private static void NoArrowsStuckPostfix(TaleWorlds.MountAndBlade.Agent attachedAgent)
    {
        try
        {
            if (!CrestConfig.IsEnabled("NoArrowsStuck", defaultValue: false)) return;
            if (attachedAgent == null) return;
            int count = attachedAgent.GetAttachedWeaponsCount();
            if (count > 0) attachedAgent.DeleteAttachedWeapon(count - 1);
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "NoArrowsStuck", ex); }
    }

    // Param names firstHero/secondHero match v1.4.2's
    // DefaultMarriageModel.GetClanAfterMarriage signature -- Harmony binds by name.
    private static void MarriageStaysInClanPostfix(object firstHero, object secondHero, ref object __result)
    {
        try
        {
            if (!CrestConfig.IsEnabled("MarriageStaysInClan", defaultValue: false)) return;
            if (firstHero == null && secondHero == null) return;
            var clanType = (firstHero ?? secondHero)!.GetType().GetProperty("Clan")?.GetValue(firstHero ?? secondHero)?.GetType();
            if (clanType == null) return;
            var pc = clanType.GetProperty("PlayerClan", BindingFlags.Public | BindingFlags.Static)?.GetValue(null);
            if (pc == null) return;

            object? Clan(object h) => h?.GetType().GetProperty("Clan")?.GetValue(h);
            if (Clan(firstHero!) == pc || Clan(secondHero!) == pc) __result = pc;
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "MarriageStaysInClan", ex); }
    }

    private static void PregnancyChanceUncappedPostfix(ref float __result)
    {
        try
        {
            if (!CrestConfig.IsEnabled("PregnancyChanceUncapped", defaultValue: false)) return;
            var floor = CrestConfig.GetFloat("PregnancyMinChance", 0.05f); // 5% minimum
            if (__result < floor) __result = floor;
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "PregnancyChanceUncapped", ex); }
    }

    private static void UnlockAllSmithingRecipesPostfix(ref bool __result)
    {
        if (CrestConfig.IsEnabled("UnlockAllSmithingRecipes", defaultValue: false))
            __result = true;
    }

    // Phase Y.19: LifelongLearning. CalculateLearningRate returns an
    // ExplainedNumber struct. We don't have a hard ref to ExplainedNumber's
    // shape across versions, so accept it as 'object' boxed and call LimitMin
    // reflectively. Postfix runs after the original computes the number.
    //
    // Phase Z.4: hot path -- called on every skill XP grant during combat.
    // Cache the per-Type reflection lookups (ResultNumber prop + LimitMin
    // method) and reuse a [ThreadStatic] args array so the per-call
    // allocation drops from "new object[1] every call" to "fill args[0]".
    // Sentinel record so a Type that genuinely lacks the members caches
    // a single null and short-circuits subsequent calls without retrying
    // GetProperty/GetMethod.
    private readonly struct LifelongLearningRefl
    {
        public readonly PropertyInfo? ResProp;
        public readonly MethodInfo?   LimitMin;
        public LifelongLearningRefl(PropertyInfo? r, MethodInfo? m) { ResProp = r; LimitMin = m; }
        public bool Bound => ResProp != null && LimitMin != null;
    }
    private static readonly ConcurrentDictionary<Type, LifelongLearningRefl> _lifelongCache = new();
    private static LifelongLearningRefl GetLifelongRefl(Type t)
    {
        return _lifelongCache.GetOrAdd(t, type =>
        {
            try
            {
                var r = type.GetProperty("ResultNumber");
                var m = type.GetMethod("LimitMin", new[] { typeof(float) });
                return new LifelongLearningRefl(r, m);
            }
            catch { return new LifelongLearningRefl(null, null); }
        });
    }

    // Reusable single-slot args buffer. ThreadStatic so we don't pay
    // for thread-safety on a value the caller fills synchronously.
    [ThreadStatic] private static object[]? _lifelongArgsTL;

    private static void LifelongLearningPostfix(ref object __result)
    {
        try
        {
            if (!CrestConfig.IsEnabled("LifelongLearning", defaultValue: false)) return;
            if (__result == null) return;
            var min = CrestConfig.GetFloat("LifelongLearningMinRate", 0.5f);
            var refl = GetLifelongRefl(__result.GetType());
            if (!refl.Bound) return;

            // Read the boxed struct's current ResultNumber. Unboxes once; OK.
            var rawCurrent = refl.ResProp!.GetValue(__result);
            if (rawCurrent is not float current) return;
            if (current >= min) return;

            var args = _lifelongArgsTL ??= new object[1];
            args[0] = min;
            // ExplainedNumber is a struct so Invoke mutates our boxed copy in
            // place -- write the updated boxed instance back to __result.
            refl.LimitMin!.Invoke(__result, args);
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "LifelongLearning", ex); }
    }

    // Phase Y.20: Achievement Unblocker. Returning false from a prefix tells
    // Harmony to skip the original method entirely. So when the toggle is on,
    // DeactivateAchievements becomes a no-op -- nothing in the campaign can
    // turn the achievement system off.
    // Phase Y.20-rewrite: single postfix on the upstream cheat-detection.
    // SandBox.CampaignBehaviors.DumpIntegrityCampaignBehavior.IsGameIntegrityAchieved
    // is a static bool method that returns false (achievements should be
    // disabled) when one of: CheckCheatUsage, CheckIfModulesAreDefault, or
    // CheckIfVersionIntegrityIsAchieved fails. Replacing __result with true
    // when our toggle is on makes the entire achievement system treat the
    // run as clean, and DeactivateAchievements is never called. Every On*
    // handler subscribes and runs normally, so achievement progress
    // accumulates correctly.
    //
    // The 'reason' parameter is an out TextObject that the original method
    // populates with a localization key ("Achievements are disabled due to
    // unofficial modules" etc.) when integrity fails. We clear it to null on
    // success so the consumer's Information toast gets a clean state.
    private static void GameIntegrityPostfix(ref TaleWorlds.Localization.TextObject? reason, ref bool __result)
    {
        try
        {
            if (!CrestConfig.IsEnabled("EnableAchievementsWithMods", defaultValue: false)) return;
            if (__result) return; // already true -- nothing to override
            __result = true;
            reason = null;
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "GameIntegrityPostfix", ex); }
    }

    // Y.20-fix3: prefix on AchievementsCampaignBehavior.DeactivateAchievements.
    // The Y.20-rewrite GameIntegrityPostfix only blocks calls that go through
    // the cheat-detection path. But AchievementsCampaignBehavior persists
    // _deactivateAchievements via SyncData -- once the field is true in a
    // save (from prior runs before the patch worked), every load triggers
    // the "{=Z9mcDuDi}Achievements are disabled!" popup directly. Returning
    // false from this prefix skips the entire DeactivateAchievements body
    // (popup + field write + every other side effect) when our toggle is on.
    // Existing saves with the flag persisted still load fine; the popup just
    // never fires.
    private static bool DeactivateAchievementsPrefix()
    {
        try
        {
            if (!CrestConfig.IsEnabled("EnableAchievementsWithMods", defaultValue: false)) return true;
            DiagOnce("achievements-deactivate-blocked",
                "AchievementsWithMods: blocked DeactivateAchievements call");
            return false; // skip original -- no popup, no field write, no side effects
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "DeactivateAchievementsPrefix", ex);
            return true; // fail-open: let original run
        }
    }

    // Phase Y.4a: prefix returning false skips RTSCamera's broken
    // Prefix_OnTick body. RTSCamera's prefix used to inject ___Agent and
    // ____lastOffShipCheckTime field references that no longer match
    // NavalDLC's AgentNavalComponent layout, causing TargetParameterCountException
    // at runtime. Default toggle ON since the alternative is the user
    // crashing in naval missions.
    private static bool RTSCameraNavalNoOpPrefix(ref bool __result)
    {
        if (!CrestConfig.IsEnabled("EnableRTSCameraNavalShim", defaultValue: true)) return true;
        // Skip the original method. RTSCamera's Prefix_OnTick is a Harmony
        // PREFIX itself -- returning bool to indicate "run original" (true)
        // or "skip original" (false). We force __result = true so the
        // game's vanilla AgentNavalComponent.OnTick runs normally. Our
        // own return false skips RTSCamera's prefix body, avoiding the crash.
        __result = true;
        return false;
    }

    // Phase Y.12c: Battle Convergence has been moved out of this file entirely.
    // It used to be a Harmony postfix on PlayerEncounter.CheckNearbyPartiesToJoinPlayerMapEvent,
    // gated through 17 reflection cache fields and a lazy resolver. After 6 fix
    // iterations (fix2..fix6) the feature still never fired in-game -- because we
    // were patching the wrong layer. Reinforcement System (Nexus #6501) does the
    // same thing as a MissionBehavior on the in-mission spawn pipeline, NOT a
    // campaign-map postfix. The clean-room rewrite lives in CrestBattleConvergence.cs
    // and is hooked from SubModule.OnMissionBehaviorInitialize. All the reflection
    // bookkeeping below has been deleted.

    // Phase Y.12: Reinforcement system. Postfix on MissionSpawnSettings.CreateDefaultSpawnSettings()
    // mutates the returned struct in-place via its property setters. All values
    // are config-driven so the user can dial waves up or down per their taste.
    //
    // Vanilla defaults (per Cecil-decompile of v1.4.2):
    //   GlobalReinforcementInterval        ~ 30s
    //   ReinforcementBatchPercentage       ~ 0.05 (5% of remaining troops per wave)
    //   MaximumReinforcementWaveCount      ~ 8
    //   ReinforcementWavePercentage        ~ 0.20
    //
    // CREST overrides:
    //   ReinforcementWaveMultiplier (default 1.5x) scales BatchPercentage
    //     and Defender/Attacker BatchPercentage uniformly so wave size grows
    //     proportionally for both sides. Multiplier <= 1.0 = no change.
    //   ReinforcementIntervalSec (default -1 = leave vanilla) overrides the
    //     base wave interval. Set to e.g. 15.0 for twice-as-frequent waves.
    //   ReinforcementMaxWaves (default -1 = leave vanilla) overrides the cap.
    //     Set higher to stretch out the battle.
    private static void SpawnSettingsPostfix(ref TaleWorlds.MountAndBlade.MissionSpawnSettings __result)
    {
        try
        {
            if (!CrestConfig.IsEnabled("EnableReinforcements", defaultValue: false)) return;

            var waveMult     = CrestConfig.GetFloat("ReinforcementWaveMultiplier", 1.5f);
            var intervalSec  = CrestConfig.GetFloat("ReinforcementIntervalSec", -1f);
            var maxWaves     = CrestConfig.GetInt  ("ReinforcementMaxWaves", -1);

            // Wave-size scaling. Clamp to avoid pathological inputs.
            if (waveMult > 1.001f && waveMult <= 4.0f)
            {
                __result.ReinforcementBatchPercentage         *= waveMult;
                __result.DefenderReinforcementBatchPercentage *= waveMult;
                __result.AttackerReinforcementBatchPercentage *= waveMult;
                __result.ReinforcementWavePercentage          *= waveMult;
                // Cap individual percentages at 1.0 (would exceed 100% otherwise).
                if (__result.ReinforcementBatchPercentage         > 1.0f) __result.ReinforcementBatchPercentage         = 1.0f;
                if (__result.DefenderReinforcementBatchPercentage > 1.0f) __result.DefenderReinforcementBatchPercentage = 1.0f;
                if (__result.AttackerReinforcementBatchPercentage > 1.0f) __result.AttackerReinforcementBatchPercentage = 1.0f;
                if (__result.ReinforcementWavePercentage          > 1.0f) __result.ReinforcementWavePercentage          = 1.0f;
            }

            // Wave timing override. -1 sentinel = "use vanilla."
            if (intervalSec >= 5f && intervalSec <= 120f)
            {
                __result.GlobalReinforcementInterval = intervalSec;
            }

            // Max-wave-count override. -1 sentinel = "use vanilla."
            if (maxWaves >= 1 && maxWaves <= 32)
            {
                __result.MaximumReinforcementWaveCount = maxWaves;
            }
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "Reinforcements", ex); }
    }

    // Phase Y.21: Tavern companion multiplier. Multiplier 1 = vanilla (no extra
    // spawns), 2 = double, 3 = triple. Calls TrySpawnNewCompanion (mult-1) extra
    // times per daily tick via reflection -- avoids a hard reference to the
    // private method.
    private static readonly System.Reflection.MethodInfo _trySpawnNewCompanion =
        AccessTools2.TypeByName("TaleWorlds.CampaignSystem.CampaignBehaviors.CompanionsCampaignBehavior")
            ?.GetMethod("TrySpawnNewCompanion", BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public);

    private static void CompanionDailyTickPostfix(object __instance)
    {
        try
        {
            int mult = CrestConfig.GetInt("TavernCompanionMultiplier", 1);
            if (mult <= 1 || _trySpawnNewCompanion == null) return;
            // Vanilla DailyTick already called TrySpawnNewCompanion once.
            // Call it (mult-1) more times for the multiplier effect.
            for (int i = 1; i < mult && i < 10; i++)
                _trySpawnNewCompanion.Invoke(__instance, null);
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "TavernCompanions.DailyTick", ex); }
    }

    // Phase Y.21-fix: _desiredTotalCompanionCount returns Single (float),
    // not Int32 -- Harmony rejects __result type mismatches at bind time
    // with "Cannot assign method return type System.Single to __result
    // type System.Int32". Switch to float.
    private static void DesiredCompanionCountPostfix(ref float __result)
    {
        int mult = CrestConfig.GetInt("TavernCompanionMultiplier", 1);
        if (mult > 1 && mult <= 10) __result *= mult;
    }

    private static readonly ConcurrentDictionary<string, byte> _diagOnceSeen = new();
    private static void DiagOnce(string key, string msg)
    {
        if (_diagOnceSeen.TryAdd(key, 0)) CrestDiag.Log(Source, msg);
    }
}
