using System;
using System.Collections.Generic;
using System.Linq;

using TaleWorlds.Core;
using TaleWorlds.MountAndBlade;

namespace Bannerlord.Harmony;

/// <summary>
/// Phase Y.3 -- the swap-logic half of CompanionHotswap. Tracks the player's
/// hero agent, exposes a list of swappable companions on the player team, and
/// performs the swap by toggling agent Controller types and reassigning the
/// PlayerTeam command authority to the new agent.
/// </summary>
internal sealed class CrestCompanionSwapBehavior : MissionBehavior
{
    private Agent? _playerHeroAgent;

    // Phase Z.4 P1-7: cache the companion-agent list and rebuild only when
    // the roster has plausibly changed. Prevents a fresh List<Agent> + LINQ
    // pipeline allocation per UI render call (CrestCompanionSelectBehavior
    // queries this list ~3-5 times per frame while the swap menu is open).
    // Dirty flag is flipped on agent build/removal, and once per mission tick
    // as a coarse safety net for IsActive() flips we don't see directly.
    private readonly List<Agent> _cachedCompanions = new(8);
    private bool _cacheDirty = true;

    public override MissionBehaviorType BehaviorType => (MissionBehaviorType)1;

    public override void OnAgentBuild(Agent agent, Banner banner)
    {
        if (_playerHeroAgent == null && agent.IsMainAgent)
            _playerHeroAgent = agent;
        _cacheDirty = true;
    }

    public override void OnAgentRemoved(Agent affectedAgent, Agent affectorAgent, AgentState agentState, KillingBlow blow)
    {
        _cacheDirty = true;
    }

    public override void OnAgentDeleted(Agent affectedAgent)
    {
        _cacheDirty = true;
    }

    // Phase Z.4 P1-7: coarse refresh tick counter. The cache is invalidated
    // every Nth OnMissionTick so IsActive() transitions we don't get a
    // direct callback for (status effects, knockdowns) eventually re-render.
    // 30 ticks ≈ half a second at 60Hz mission tick rate, fast enough to
    // feel responsive, slow enough that the per-frame UI calls cluster.
    private int _refreshTickCounter;
    private const int RefreshIntervalTicks = 30;

    public override void OnMissionTick(float dt)
    {
        try
        {
            if (_playerHeroAgent == null && Mission.Current?.MainAgent != null)
                _playerHeroAgent = Mission.Current.MainAgent;

            var current = Mission.Current?.MainAgent;
            if (IsPlayerControlledHeroOnPlayerTeam(current))
                ApplyPlayerCommandAuthority(current!);

            if (++_refreshTickCounter >= RefreshIntervalTicks)
            {
                _refreshTickCounter = 0;
                _cacheDirty = true;
            }
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(nameof(CrestCompanionSwapBehavior), "OnMissionTick", ex);
        }
    }

    public override void OnAgentControllerSetToPlayer(Agent agent)
    {
        base.OnAgentControllerSetToPlayer(agent);
        if (IsPlayerControlledHeroOnPlayerTeam(agent))
            ApplyPlayerCommandAuthority(agent);
    }

    public void SwapToAgent(Agent agent)
    {
        var mission = Mission.Current;
        if (mission == null || agent == null || !agent.IsActive() || agent == mission.MainAgent) return;

        try
        {
            var prev = mission.MainAgent;
            if (prev != null)
                prev.Controller = AgentControllerType.AI;

            mission.SetPlayerCanTakeControlOfAnotherAgentWhenDead();
            agent.Controller = AgentControllerType.Player;
            ApplyPlayerCommandAuthority(agent);
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(nameof(CrestCompanionSwapBehavior), "SwapToAgent", ex);
        }
    }

    public List<Agent> GetCompanionAgents()
    {
        // Phase Z.4 P1-7: dirty-flag-driven cache. Multiple calls per frame
        // (UI render hot path) reuse the same List instance.
        if (!_cacheDirty) return _cachedCompanions;

        _cachedCompanions.Clear();
        var team = Mission.Current?.PlayerTeam;
        if (team == null)
        {
            _cacheDirty = false;
            return _cachedCompanions;
        }

        if (_playerHeroAgent != null && _playerHeroAgent.IsActive())
            _cachedCompanions.Add(_playerHeroAgent);

        // Avoid LINQ Where+OrderBy enumeration alloc; collect into the cache,
        // then sort in place via List<T>.Sort with a stable comparer.
        foreach (var a in team.ActiveAgents)
        {
            if (a == null) continue;
            if (!a.IsHero) continue;
            if (a == _playerHeroAgent) continue;
            if (!a.IsActive()) continue;
            _cachedCompanions.Add(a);
        }
        // Player hero (index 0) stays first; sort the rest by display name.
        // Comparer<T>.Default would compare references, so use a delegated comparison.
        if (_cachedCompanions.Count > 1)
        {
            var first = _cachedCompanions[0];
            // Sort the [1..] slice by name. List.Sort doesn't support range,
            // so we sort the whole list and re-anchor the player hero at 0.
            _cachedCompanions.Sort((x, y) => string.Compare(x?.Name, y?.Name, StringComparison.Ordinal));
            // Move player hero back to index 0 if sort displaced it.
            if (first != null)
            {
                var idx = _cachedCompanions.IndexOf(first);
                if (idx > 0)
                {
                    _cachedCompanions.RemoveAt(idx);
                    _cachedCompanions.Insert(0, first);
                }
            }
        }

        _cacheDirty = false;
        return _cachedCompanions;
    }

    private static bool IsPlayerControlledHeroOnPlayerTeam(Agent? agent)
    {
        var team = Mission.Current?.PlayerTeam;
        if (team == null || agent == null || !agent.IsHero || !agent.IsActive()) return false;
        return agent.Team == team;
    }

    private static void ApplyPlayerCommandAuthority(Agent agent)
    {
        var team = agent.Team;
        if (team == null) return;

        team.SetPlayerRole(true, false);
        team.GeneralAgent = agent;
        team.PlayerOrderController.Owner = agent;
        foreach (var formation in team.FormationsIncludingSpecialAndEmpty)
        {
            if (formation == null) continue;
            formation.PlayerOwner = agent;
            formation.SetControlledByAI(false, false);
        }
    }
}
