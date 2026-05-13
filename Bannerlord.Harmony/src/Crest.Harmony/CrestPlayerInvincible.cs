using System;

using TaleWorlds.CampaignSystem;
using TaleWorlds.Core;
using TaleWorlds.MountAndBlade;

namespace Bannerlord.Harmony;

/// <summary>
/// Y.12d-fix24: keep the player hero's agent at full health every tick.
/// Gated on EnablePlayerInvincible (default false). Implemented as a
/// MissionBehavior so it works in any mission type without Harmony patches
/// (the prior PlayerNoFlinch Harmony approach was inert because the loose-
/// typed prefix can't mutate the Blow struct).
///
/// Y.31: target Hero.MainHero specifically, NOT Mission.MainAgent. The
/// MainAgent property follows the camera focus -- when the player switches
/// to free cam or controls a companion via Companion Hotswap, MainAgent
/// becomes the companion and the actual player hero (off-camera) gets no
/// protection and dies normally. Caching the player-hero agent reference
/// keeps the per-tick cost the same as the old MainAgent approach.
///
/// Mechanism: set playerAgent.Health = HealthLimit each tick. Damage
/// still fires (animation flinch, hit decals, etc.) but the agent never
/// dies because health resets immediately. Cheap -- one comparison + one
/// assignment per tick when active.
/// </summary>
internal sealed class CrestPlayerInvincible : MissionBehavior
{
    private const string Source = nameof(CrestPlayerInvincible);

    // Z.6 perf-B: cache the master toggle so we don't call CrestConfig.IsEnabled
    // 60 times per second. Refreshed every 500ms which matches CrestConfig's
    // own mtime-throttle window -- no observable lag for the user, big win for
    // hot-path tick cost.
    private bool _enabledCached;
    private float _configCheckAccum;
    private const float ConfigCheckIntervalSec = 0.5f;

    // Y.31: cache the player hero's agent. Re-resolved when invalidated.
    private Agent? _playerHeroAgent;

    public override MissionBehaviorType BehaviorType => (MissionBehaviorType)1;

    public override void OnMissionTick(float dt)
    {
        try
        {
            _configCheckAccum += dt;
            if (_configCheckAccum >= ConfigCheckIntervalSec)
            {
                _configCheckAccum = 0f;
                _enabledCached = CrestConfig.IsEnabled("EnablePlayerInvincible", defaultValue: false);
            }
            if (!_enabledCached) return;

            var mission = Mission.Current;
            if (mission == null) return;
            // Y.12d-fix30: only act when the mission is in active battle mode.
            // During deployment, transitions, or post-battle results, MainAgent
            // can be in a half-disposed state where mutating Health corrupts
            // engine internals and contributes to hard-crashes during heavy
            // spawning.
            if (mission.Mode != MissionMode.Battle) return;
            if (mission.IsMissionEnding) return;

            // Y.31: resolve player hero's agent (NOT Mission.MainAgent).
            // MainAgent follows the camera focus; we want the actual player
            // hero regardless of who the user is currently controlling. Cache
            // the agent reference and re-resolve only when invalidated.
            var playerHero = Hero.MainHero;
            if (playerHero == null) return;
            var playerCharacter = playerHero.CharacterObject;
            if (playerCharacter == null) return;

            if (_playerHeroAgent == null
                || !_playerHeroAgent.IsActive()
                || _playerHeroAgent.Mission != mission
                || _playerHeroAgent.Character != playerCharacter)
            {
                _playerHeroAgent = null;
                var agentList = mission.Agents;
                if (agentList != null)
                {
                    for (int i = 0; i < agentList.Count; i++)
                    {
                        var a = agentList[i];
                        if (a == null) continue;
                        if (!a.IsHuman) continue;
                        if (a.Character == playerCharacter)
                        {
                            _playerHeroAgent = a;
                            break;
                        }
                    }
                }
            }

            var main = _playerHeroAgent;
            if (main == null) return;
            if (!main.IsActive()) return;
            if (main.HealthLimit <= 0f) return;     // sanity: no negative/zero limits
            if (main.Health <= 0f) return;          // already dead -- don't try to revive
            if (main.Health < main.HealthLimit)
                main.Health = main.HealthLimit;
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "OnMissionTick", ex);
        }
    }
}

/// <summary>
/// Y.32 / Phase Y.28: typed Harmony prefix on Mission.RegisterBlow that
/// clamps incoming damage to 0 when the victim is the player hero and
/// EnablePlayerInvincible is on.
///
/// Why typed: PlayerNoFlinch tried this with reflection-based bind in
/// CrestCampaignTweaks and was inert because loose-typed prefix can't
/// mutate the ref Blow struct. This class uses a typed handler bound
/// via harmony.Patch + HarmonyMethod, which DOES allow ref-struct
/// mutation (same pattern CrestCutThroughEveryone uses for ref
/// AttackCollisionData mutation).
///
/// Combined with the per-tick health peg in CrestPlayerInvincible,
/// this gives true invincibility: hits don't register damage at all,
/// AND health stays full as a belt-and-suspenders for any path that
/// somehow bypasses RegisterBlow.
/// </summary>
internal static class CrestPlayerInvincibleDamageClamp
{
    private const string Source = nameof(CrestPlayerInvincibleDamageClamp);
    private static bool _patched;
    private static System.Reflection.FieldInfo? _blowDamageField;
    private static System.Reflection.FieldInfo? _collisionDamageField;
    private static bool _fieldsResolved;

    public static void TryApply(HarmonyLib.Harmony harmony)
    {
        if (_patched) return;
        try
        {
            var target = HarmonyLib.BUTR.Extensions.AccessTools2.Method(typeof(TaleWorlds.MountAndBlade.Mission), "RegisterBlow");
            if (target == null)
            {
                CrestDiag.Log(Source, "Mission.RegisterBlow not found - skipping damage-clamp patch");
                _patched = true;
                return;
            }

            // Try the most common parameter name for the Blow ref param.
            // If our prefix's parameter name doesn't match the original,
            // Harmony rejects the patch with a clear error.
            var hm = new HarmonyLib.HarmonyMethod(typeof(CrestPlayerInvincibleDamageClamp), nameof(RegisterBlowPrefix));
            harmony.Patch(target, prefix: hm);
            _patched = true;
            CrestDiag.Log(Source, "patched Mission.RegisterBlow (damage clamp for player hero)");
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "TryApply", ex);
            _patched = true;  // do not retry on error
        }
    }

    // Typed prefix. Harmony binds parameters by NAME, so the names must
    // match Mission.RegisterBlow's actual signature. In v1.4.x the params
    // are typically: attacker, victim, hitEntity, b (Blow), collisionData,
    // attackerWeapon, etc. We only declare the ones we need to inspect/mutate.
    public static void RegisterBlowPrefix(TaleWorlds.MountAndBlade.Agent victim, ref TaleWorlds.MountAndBlade.Blow b)
    {
        try
        {
            if (victim == null) return;
            if (!CrestConfig.IsEnabled("EnablePlayerInvincible", defaultValue: false)) return;

            // Match victim against the player hero's character object.
            var playerHero = TaleWorlds.CampaignSystem.Hero.MainHero;
            if (playerHero == null) return;
            var playerCharacter = playerHero.CharacterObject;
            if (playerCharacter == null) return;
            if (!ReferenceEquals(victim.Character, playerCharacter)) return;

            // Clamp damage so the engine treats this hit as 0 inflicted damage.
            // We can't easily mutate every nested damage field (e.g.
            // AttackCollisionData also carries InflictedDamage in some code
            // paths) without ref params here, so we mutate Blow.InflictedDamage
            // and rely on the per-tick health peg as belt-and-suspenders.
            //
            // Resolve the field once via reflection. Field name in v1.4.x is
            // InflictedDamage (instance field on Blow struct).
            if (!_fieldsResolved)
            {
                try { _blowDamageField = typeof(TaleWorlds.MountAndBlade.Blow).GetField("InflictedDamage"); }
                catch { }
                _fieldsResolved = true;
            }
            if (_blowDamageField != null)
            {
                // Boxing trick to set value-type field through reflection.
                object boxed = b;
                _blowDamageField.SetValue(boxed, 0);
                b = (TaleWorlds.MountAndBlade.Blow)boxed;
            }
            // Also try direct property/field if there's a public setter
            // (different versions). Best-effort.
            try { b.InflictedDamage = 0; } catch { }
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "RegisterBlowPrefix", ex);
        }
    }
}
