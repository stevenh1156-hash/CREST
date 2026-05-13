using TaleWorlds.Library;
using TaleWorlds.MountAndBlade;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Party;

namespace Bannerlord.Harmony;

/// <summary>
/// Tactical role assigned to a spawn spot based on its terrain profile and
/// position relative to battle center. Class-aware fill routes incoming
/// agents to spots whose <see cref="ClassPref"/> matches their troop class.
/// </summary>
public enum SpotRole
{
    /// <summary>High ground with line-of-sight toward center -- archer position.</summary>
    Overlook,
    /// <summary>Closest spot to battle center on own side -- main infantry line.</summary>
    Front,
    /// <summary>Lateral left, open ground -- cavalry / flanking force.</summary>
    FlankLeft,
    /// <summary>Lateral right, open ground -- cavalry / flanking force.</summary>
    FlankRight,
    /// <summary>Adjacent to natural barrier (cliff, water, map edge) -- defensive line.</summary>
    Anchor,
    /// <summary>Far rear -- overflow + late-arriving lords.</summary>
    Reserve,
    /// <summary>Y.67: hidden position at choke/cover -- holds until enemy approaches.</summary>
    Ambush,
}

/// <summary>Class preference for a spot. Class-aware fill picks the
/// best-matching spot for each spawning agent's troop class.</summary>
public enum ClassPref
{
    InfantryPreferred,
    ArcherPreferred,
    CavalryPreferred,
    /// <summary>No strong preference -- accepts any class. Fallback role.</summary>
    Mixed,
}

/// <summary>
/// A pre-planned spawn spot for one side of a battle. Picked at mission
/// start by <see cref="CrestTerrainScan"/> based on heightmap analysis,
/// then filled by the spawn pump as lords arrive.
/// </summary>
public sealed class CrestSpot
{
    // -- terrain + identity (set at scan time, immutable after) --

    public Vec3   Anchor;
    public int    Capacity;
    public SpotRole Role;
    public ClassPref ClassPreference;
    /// <summary>Height delta vs battle center. Positive = higher ground.</summary>
    public float  HeightDelta;
    /// <summary>Comma-separated terrain tags: hill, flat, ridge, edge, slope.</summary>
    public string TerrainTag = "";
    /// <summary>Score the picker assigned to this spot (debug/diag only).</summary>
    public float  PickScore;
    public bool   IsEnemySpot;

    // -- live battle state (mutated as agents fill in) --

    /// <summary>Engine slot index (10..23). Assigned at first-fill time.</summary>
    public int    FormationIndex = -1;
    public Formation? Formation;
    public int    CurrentCount;
    /// <summary>Current captain agent (re-elected by Y.53 if killed).</summary>
    public Agent? Captain;
    /// <summary>Lords whose troops have contributed to this spot.</summary>
    public PartyBase? LeadParty;
    public int    LeadTactics = -1;

    // -- per-spot tier / variant (replaces per-pool tier logic) --

    public bool   AdvanceApplied;
    public bool   ShieldWallActive;
    public bool   CircleActive;
    public int    LastParityDelta = int.MinValue;
    public float  LastParityCheck = -1f;
    public float  LastReassertAt  = -1f;
    public MovementOrder    IntendedMovement    = MovementOrder.MovementOrderStop;
    public ArrangementOrder IntendedArrangement = ArrangementOrder.ArrangementOrderLine;

    /// <summary>Convenience: short label for diag (e.g. "ally.OVERLOOK[0]").</summary>
    public string DiagLabel(int idx, string sideTag)
        => $"{sideTag}.{Role}[{idx}]";
}
