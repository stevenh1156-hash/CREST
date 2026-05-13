namespace Bannerlord.Harmony;

/// <summary>
/// Pure-state Y.54 formation override rules. Decoupled from <c>Formation</c>
/// and other TaleWorlds types so the sim harness (Crest.Harmony.Sim) can
/// call exactly the same logic without needing the full Bannerlord runtime.
///
/// <para>
/// The production caller in <c>LogFormationSnapshot</c> reads primitives off
/// the live <c>Formation</c> (units, weights, distances, engineMove name)
/// and calls <see cref="Evaluate"/>. The sim builds the same primitives
/// from a JSON scenario and calls the same method. One source of truth.
/// </para>
/// </summary>
public enum Y54Action
{
    None,
    CavUnstuck,
    BrokenRetreat,
    WanderClamp,
    /// <summary>Y.66: hold position because no line-of-sight to enemy.</summary>
    HoldNoLOS,
    /// <summary>Y.67: ambush spot holds until enemy approaches within trigger radius.</summary>
    AmbushHold,
}

/// <summary>Result of <see cref="CrestFormationRules.Evaluate"/>.</summary>
public readonly struct Y54Decision
{
    public Y54Action Action { get; }
    /// <summary>Human-readable trailer for the diag log line.</summary>
    public string Reason { get; }

    public Y54Decision(Y54Action action, string reason)
    {
        Action = action;
        Reason = reason;
    }

    public static Y54Decision None => new(Y54Action.None, string.Empty);
}

public static class CrestFormationRules
{
    /// <summary>
    /// Evaluate the three Y.54 rules against a formation's live state.
    /// Returns the first matching action, or <see cref="Y54Action.None"/>
    /// if no rule applies.
    /// </summary>
    /// <param name="isCav">true if the formation is the pool's cavalry slot</param>
    /// <param name="units">live agent count in the formation</param>
    /// <param name="retreatWeight">live <c>BehaviorRetreat.GetAiWeight()</c> value</param>
    /// <param name="anchorDist">distance from the formation's spawn anchor</param>
    /// <param name="enemyDist">distance to the nearest enemy formation centre</param>
    /// <param name="engineMove">
    /// stringified <c>MovementOrder.OrderType</c> currently active
    /// (e.g. "Advance", "StandYourGround", "Charge")
    /// </param>
    public static Y54Decision Evaluate(
        bool isCav,
        int units,
        float retreatWeight,
        float anchorDist,
        float enemyDist,
        string engineMove,
        bool losToEnemy = true,
        string spotRole = "")
    {
        // Y.67: Ambush role -- hold until enemy enters trigger radius (40m).
        // Class-pref Mixed; small balanced force pre-positioned at a choke or
        // covered approach. Evaluate this BEFORE the standard rules so an
        // ambush spot doesn't accidentally trigger wander-clamp during its
        // hidden phase.
        if (spotRole == "Ambush" && units > 0)
        {
            if (enemyDist > 40f)
            {
                return new Y54Decision(Y54Action.AmbushHold,
                    $"ambush hidden enemyD={enemyDist:F1} -> Stop");
            }
            // enemy is within trigger radius -- release hold, let engine engage.
            // Returning None means no override, normal advance behavior runs.
            return Y54Decision.None;
        }

        // Y.66: no line-of-sight to enemy. If formation is supposed to advance
        // toward an engagement but cannot SEE the enemy (terrain or structure
        // blocks LOS), holding position is more useful than charging blind
        // into a wall. Triggers only when an enemy IS in close range
        // (enemyDist<100) but invisible -- because at long range LOS is
        // expected to be obstructed by terrain.
        if (engineMove == "Advance" && enemyDist < 100f && !losToEnemy && units > 5)
        {
            return new Y54Decision(Y54Action.HoldNoLOS,
                $"no LOS at enemyD={enemyDist:F1} -> Stop");
        }


        // Rule 1: cavalry should never be a static shield wall. If a pool's
        // variant flipped to ShieldWall (because the team is outnumbered),
        // pull cav out and put them on Charge/Skein. Inf/arch can stay in
        // shield wall -- it's a real defensive posture for foot troops.
        if (isCav && units > 5 && engineMove == "StandYourGround")
        {
            return new Y54Decision(
                Y54Action.CavUnstuck,
                $"StandYourGround/ShieldWall -> Charge/Skein (units={units})");
        }

        // Rule 2: a formation broken below 25 men with engine Retreat weight
        // > 3.0 wants out. Drop the manual StandYourGround and let them
        // retreat instead of dying in place.
        if (units > 0 && units < 25 && retreatWeight > 3.0f && engineMove == "StandYourGround")
        {
            return new Y54Decision(
                Y54Action.BrokenRetreat,
                $"units={units} retreatW={retreatWeight:F2} -> Retreat");
        }

        // Rule 3: wandered with no enemy nearby. Threshold history:
        //   Y.54 original: anchorD>80 AND enemyD>100
        //   Y.58 relaxed:  anchorD>50 AND enemyD>100  (caught stranded archers)
        //   Y.68 relaxed:  anchorD>50 AND enemyD>250  (post-spot architecture)
        //
        // Y.68 reasoning: with 8 spots/side spread over the map, formations
        // legitimately march 100-250m from spawn anchor toward engagement.
        // The old enemyD>100 condition over-fired during transit (a real
        // battle showed 196 wander-clamps in ~107s with formations at
        // anchorD=144 enemyD=137 -- closing on enemy, not wandering).
        // Bumping to 250m means only TRUE wanderers (no engagement
        // anywhere within ~250m) get clamped.
        if (anchorDist > 50f && enemyDist > 250f && units > 0 && engineMove == "Advance")
        {
            return new Y54Decision(
                Y54Action.WanderClamp,
                $"anchorD={anchorDist:F1} enemyD={enemyDist:F1} -> Stop");
        }

        return Y54Decision.None;
    }

    /// <summary>
    /// Map a decision to its short name (for the override dict log line).
    /// </summary>
    public static string ActionShortName(Y54Action a) => a switch
    {
        Y54Action.CavUnstuck    => "cav-unstuck",
        Y54Action.BrokenRetreat => "broken-retreat",
        Y54Action.WanderClamp   => "wander-clamp",
        Y54Action.HoldNoLOS     => "no-los",
        Y54Action.AmbushHold    => "ambush-hold",
        _                       => "none",
    };
}
