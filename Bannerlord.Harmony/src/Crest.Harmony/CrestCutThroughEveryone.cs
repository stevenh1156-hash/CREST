using HarmonyLib;
using HarmonyLib.BUTR.Extensions;

using System;
using System.Linq;
using System.Reflection;

using TaleWorlds.Core;
using TaleWorlds.MountAndBlade;

namespace Bannerlord.Harmony;

/// <summary>
/// Phase Y.2 -- XorberaxLegacy "Cut Through Everyone" absorption.
///
/// Replicates the behavior of XorberaxLegacy.Patches.CutThroughEveryonePatch{MeleeHit,Collision}
/// and CutThroughEveryoneLogic by patching:
///
///   * <c>Mission.MeleeHitCallback</c> (postfix) -- when a melee hit lands and
///     the original logic decided <c>SlicedThrough</c>, we keep that decision
///     but set <c>inOutMomentumRemaining</c> = (inflicted/total) *
///     <c>DamageRetainedPerCut</c>, so the swing carries forward at reduced
///     momentum into subsequent agents.
///
///   * <c>MissionCombatMechanicsHelper.DecideWeaponCollisionReaction</c>
///     (postfix) -- overrides the engine's collision reaction to
///     <c>SlicedThrough</c> when our preflight passes. Without this the
///     engine often picks <c>ChoppedOff</c> / <c>Bounced</c> on the second
///     and later targets, ending the swing.
///
/// All MCM properties (master + sub-toggles + sliders) are read fresh from
/// crest.json on every call via CrestConfig (mtime-cached). Per the Phase W
/// absorption template: master OFF by default, RequireRestart=false, live
/// updates without game restart.
/// </summary>
internal static class CrestCutThroughEveryone
{
    private const string Source = nameof(CrestCutThroughEveryone);
    private static bool _patched;

    public static void TryApply(HarmonyLib.Harmony harmony)
    {
        if (_patched) return;

        // Phase Y.2 bisect: env var lets the user run a build with the
        // patches NOT applied, to isolate whether a crash is from the
        // patches or from something else. Set CREST_CUTTHROUGH_DISABLE=1
        // to short-circuit. Default behavior unchanged.
        if (Environment.GetEnvironmentVariable("CREST_CUTTHROUGH_DISABLE") == "1")
        {
            CrestDiag.Log(Source, "patches DISABLED via CREST_CUTTHROUGH_DISABLE=1 (bisect mode)");
            _patched = true;
            return;
        }

        // Phase Y.2 bisect: ALSO short-circuit if the master toggle is
        // OFF at startup. That makes the master toggle a true switch --
        // when off, no patches are even bound, so we can rule out patch
        // binding as the cause of any crash. The user can toggle back on
        // via MCM but the patches won't activate until next game launch.
        if (!CrestConfig.IsEnabled("EnableCutThroughEveryone", defaultValue: false))
        {
            CrestDiag.Log(Source, "master toggle OFF at startup -- not binding patches (toggle on + restart to enable)");
            _patched = true;
            return;
        }

        try
        {
            // Patch Mission.MeleeHitCallback
            var meleeHitTarget = AccessTools2.Method(typeof(Mission), "MeleeHitCallback");
            if (meleeHitTarget != null)
            {
                harmony.Patch(meleeHitTarget,
                    postfix: new HarmonyMethod(typeof(CrestCutThroughEveryone), nameof(MeleeHitCallbackPostfix)));
            }
            else
            {
                CrestDiag.Log(Source, "Mission.MeleeHitCallback not found - skipping melee-hit patch");
            }

            // Patch MissionCombatMechanicsHelper.DecideWeaponCollisionReaction
            var collisionTarget = AccessTools2.Method(typeof(MissionCombatMechanicsHelper), "DecideWeaponCollisionReaction");
            if (collisionTarget != null)
            {
                harmony.Patch(collisionTarget,
                    postfix: new HarmonyMethod(typeof(CrestCutThroughEveryone), nameof(DecideWeaponCollisionReactionPostfix)));
            }
            else
            {
                CrestDiag.Log(Source, "MissionCombatMechanicsHelper.DecideWeaponCollisionReaction not found - skipping collision patch");
            }

            _patched = true;
            CrestDiag.Log(Source, "patched cut-through hooks (gated on EnableCutThroughEveryone master toggle)");
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "TryApply", ex);
        }
    }

    /// <summary>
    /// Postfix on <c>Mission.MeleeHitCallback</c>. If the engine decided
    /// SlicedThrough and our gate passes, retain a fraction of the swing
    /// momentum so the weapon carries into subsequent targets.
    /// </summary>
    private static void MeleeHitCallbackPostfix(
        ref AttackCollisionData collisionData, Agent attacker, Agent victim,
        ref float inOutMomentumRemaining, ref MeleeCollisionReaction colReaction)
    {
        try
        {
            if (colReaction != MeleeCollisionReaction.SlicedThrough) return;
            int total = collisionData.InflictedDamage + collisionData.AbsorbedByArmor;
            if (total < 1) return;
            if (!ShouldCutThrough(collisionData, attacker, victim)) return;

            var ratio = (float)collisionData.InflictedDamage / total;
            var retained = CrestConfig.GetFloat("CutThroughDamageRetainedPerCut", 0.8f);
            inOutMomentumRemaining = ratio * retained;
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "MeleeHitCallbackPostfix", ex);
        }
    }

    /// <summary>
    /// Postfix on <c>MissionCombatMechanicsHelper.DecideWeaponCollisionReaction</c>.
    /// When our gate passes, force the reaction to SlicedThrough so the
    /// swing keeps going.
    /// </summary>
    private static void DecideWeaponCollisionReactionPostfix(
        ref AttackCollisionData collisionData, Agent attacker, Agent defender,
        ref MeleeCollisionReaction colReaction)
    {
        try
        {
            if (!ShouldCutThrough(collisionData, attacker, defender)) return;
            colReaction = MeleeCollisionReaction.SlicedThrough;
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "DecideWeaponCollisionReactionPostfix", ex);
        }
    }

    private static bool ShouldCutThrough(AttackCollisionData collisionData, Agent attacker, Agent victim)
    {
        // Master gate
        if (!CrestConfig.IsEnabled("EnableCutThroughEveryone", defaultValue: false)) return false;

        if (attacker == null || victim == null) return false;
        var weapon = attacker.WieldedWeapon;
        if (weapon.Item == null) return false;

        // EnableOnlyKilledUnitsCutThrough: skip cut-through if victim is still alive.
        if (CrestConfig.IsEnabled("CutThroughOnlyKilledUnits", defaultValue: false))
        {
            if ((int)victim.Health > 0) return false;
        }

        // EnableFriendlyUnitsBlockCutThrough: skip when attacker and victim are
        // on the same team. Default ON (typical desired behavior).
        var sameTeam = attacker.Team != null && victim.Team != null && attacker.Team == victim.Team;
        if (sameTeam && CrestConfig.IsEnabled("CutThroughFriendliesBlock", defaultValue: true)) return false;

        // EnableAICutThrough: by default only the player gets cut-through. If on,
        // AI agents also get it.
        if (!CrestConfig.IsEnabled("CutThroughAlsoForAI", defaultValue: false))
        {
            if (!attacker.IsMainAgent) return false;
        }

        // Weapon class filter -- only slashing weapons cut through. Polearms,
        // swords, axes, two-handed variants. Skip blunt (mace), bows, throwing,
        // crossbows, javelins.
        var primaryWeapon = weapon.Item.Weapons?.FirstOrDefault();
        if (primaryWeapon == null) return false;
        var wepClass = primaryWeapon.WeaponClass;
        if (!IsSlashingWeaponClass(wepClass)) return false;

        // Direction filter -- swing directions only (not thrust). The engine
        // categorizes attacks as Up/Down/Left/Right/None; thrusts have
        // direction=None and shouldn't cut through. Slashes (Left/Right) and
        // overheads (Up/Down) all qualify for slashing weapons.
        var dir = collisionData.AttackDirection;
        if (dir == Agent.UsageDirection.None || dir == Agent.UsageDirection.AttackEnd) return false;

        // Armor cut-through threshold: need at least
        // PercentageOfInflictedDamageRequiredToCutThroughArmor of the total
        // (inflicted+absorbed) damage to actually have been inflicted. Otherwise
        // the swing got eaten by armor and shouldn't carry forward.
        int total = collisionData.InflictedDamage + collisionData.AbsorbedByArmor;
        if (total < 1) return false;
        var ratio = (float)collisionData.InflictedDamage / total;
        var threshold = CrestConfig.GetFloat("CutThroughArmorThreshold", 0.5f);
        return ratio >= threshold;
    }

    private static bool IsSlashingWeaponClass(WeaponClass wc)
    {
        switch (wc)
        {
            case WeaponClass.OneHandedSword:
            case WeaponClass.TwoHandedSword:
            case WeaponClass.OneHandedAxe:
            case WeaponClass.TwoHandedAxe:
            case WeaponClass.OneHandedPolearm:
            case WeaponClass.TwoHandedPolearm:
            case WeaponClass.LowGripPolearm:
                return true;
            default:
                return false;
        }
    }
}
