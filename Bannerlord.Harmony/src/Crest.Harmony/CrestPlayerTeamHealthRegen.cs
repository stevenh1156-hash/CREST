using System;

using TaleWorlds.MountAndBlade;

namespace Bannerlord.Harmony;

/// <summary>
/// Phase Y.5b -- 1 HP/sec passive health regeneration for player-team agents
/// during regular missions. Skipped during tournament missions to preserve
/// the intended challenge there. Configurable rate via crest.json
/// (PlayerHealthRegenPerSec, default 1.0).
///
/// Implemented as a MissionBehavior added to every mission via
/// <see cref="CrestCampaignTweaks"/> if the EnablePlayerHealthRegen toggle
/// is on. No Harmony patch needed.
/// </summary>
internal sealed class CrestPlayerTeamHealthRegen : MissionBehavior
{
    private const string Source = nameof(CrestPlayerTeamHealthRegen);
    private float _accumulator;

    public override MissionBehaviorType BehaviorType => (MissionBehaviorType)1;

    public override void OnMissionTick(float dt)
    {
        // Phase Z.1 perf: accumulate FIRST so we only spend CPU on real work
        // once per second. Config + mission lookups happen behind the gate so
        // the 59 idle ticks per second cost ~5 ns (one float add + compare).
        _accumulator += dt;
        if (_accumulator < 1f) return;

        try
        {
            if (!CrestConfig.IsEnabled("EnablePlayerHealthRegen", defaultValue: false))
            {
                // Drain the accumulator even when disabled so we don't spike
                // when the toggle flips on after a long disabled period.
                _accumulator = 0f;
                return;
            }
            var mission = Mission.Current;
            if (mission == null) { _accumulator = 0f; return; }
            if (mission.PlayerTeam == null) { _accumulator = 0f; return; }

            _accumulator -= 1f;

            var rate = CrestConfig.GetFloat("PlayerHealthRegenPerSec", 1f);
            if (rate <= 0f) return;

            // Indexed loop avoids the foreach enumerator allocation on
            // MBReadOnlyList/MBList collections (per-second so not critical,
            // but free).
            var active = mission.PlayerTeam.ActiveAgents;
            for (int i = 0; i < active.Count; i++)
            {
                var agent = active[i];
                if (agent == null || !agent.IsActive() || !agent.IsHuman) continue;
                if (agent.Health >= agent.HealthLimit) continue;
                agent.Health = Math.Min(agent.HealthLimit, agent.Health + rate);
            }
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "OnMissionTick", ex);
        }
    }
}
