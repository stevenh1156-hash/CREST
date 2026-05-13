# Troop-placement mission -- progress tracker

Read together with HERALD-MISSION-troop-placement.md.

## Battle log

   [x] Battle 1 (baseline)        DONE 2026-05-09 20:39 local
                                  faction: Battania (vs ?)
                                  6 ally spots, all populated, no
                                  missing-class issue
                                  finding: 3 of 6 spots stuck on
                                  StandYourGround based on enemyD
                                  (further-from-enemy spots hold)

   [_] Battle 2 (StandYourGround
                 distance bias)   pending. Goal: confirm the
                                  distance-from-enemy decision is the
                                  cause. Need a battle with at least
                                  one archer-class faction (Empire,
                                  Aserai, Vlandia, Sturgia archers).

   [_] Battle 3 (TryAutoDelegate) DEPRIORITIZED -- Battle 1 showed
                                  every spot has captain + weights, so
                                  attachment is not the bug.

   [_] Battle 4 (initial-hold)    DEPRIORITIZED -- Battle 1 cycles
                                  start at 20:34:24 with engineMove
                                  set, so hold-window timing is fine.

   [_] Battle 5 (anchor sanity)   POSSIBLY USEFUL -- spots 3, 4, 5
                                  have anchorD < 2.5 so they ARE at
                                  anchor; they just won't leave it.
                                  Likely not the bug.

## Findings as they come in

### Battle 1 (2026-05-09 20:39)

   - 6 ally spots reported via Y.42 cycles (76 cycles total over
     ~5 min battle).
   - Symptom is NOT "infantry stuck globally" -- spot 0 (93 inf
     units) is Advancing fine. The split is by DISTANCE from enemy.
   - Spots 0, 1, 2 (enemyD < 105m) -> Advance / Charge
   - Spots 3, 4, 5 (enemyD > 70m, two of them > 145m) -> StandYourGround
   - wantMove == engineMove in every cycle, so the engine is doing
     what we tell it. The bug is in OUR decision.

### Reframed hypothesis (replaces H1-H5)

   H6.  Distance-gated StandYourGround.  Y.54 override logic (or
        Y.65/Y.66 spot-tactic logic) reads enemyD and falls through
        to "hold position" when enemyD is large. Result: rear spots
        sit forever even when no engagement is happening near them.
        The fix is one of:
          - reduce the distance threshold for "hold"
          - add a fallback: if no other ally spot is engaging, ALL
            spots should advance toward the enemy main mass
          - add a "rally" tick: every N seconds, far-back spots
            walk forward to within engagement range of forward spots

   H7.  Role-driven hold.  CrestSpot.cs SpotRole enum has Reserve,
        Anchor, Ambush -- spots assigned to those roles MAY be
        intentionally on StandYourGround. If 3 of 6 spots got
        Reserve / Anchor / Ambush roles by accident, that explains
        the symptom.

### Open question for Battle 2

   - Find a faction with an archer-heavy army to confirm whether
     archer spots populate at all (the original "archers don't form"
     report needs an archer party to test).
   - Capture the SpotRole assignment for each spot (this isn't in
     the Y.42 line today; needs a one-shot probe log).

### Bisect findings (2026-05-09 night, 30-min timebox)

Built source-tree-restored DLL with various subsets disabled to find
the CTD source. State left in place: source tree has the .fuse_hidden
ghost contents (still suspect), deployed DLL rolled back to .bak
8999B4950CFB so the game stays playable.

Tests run:
   T1 -- Y.74 finalizer stubbed                  -> CTD same way (Y.74 INNOCENT)
   T2 -- EnableBattleConvergence=false in JSON   -> CLEAN (no MissionLogic = no crash)
   T3 -- AfterStart, OnTeamDeployed, OnMission-
         ModeChange all early-return; convergence
         re-enabled                              -> CTD during battle load (so far)
   T4 -- + OnMissionTick early-return            -> CLEAN through battle load,
                                                    CTD'd MID-BATTLE no error

Conclusions:
   - CTD source is INSIDE CrestBattleConvergenceLogic.cs.
   - It is NOT in: AfterStart, OnTeamDeployed, OnMissionModeChange,
     OnMissionTick.
   - It is NOT at object-construction time (T4 ran fine through
     battle load with object attached).
   - It IS in one of the still-active overrides that fire mid-battle:
        OnAgentRemoved (line 784)
        OnEarlyAgentRemoved (line 885)
        OnAgentPanicked (line 899)
        OnMissionResultReady (line 911)
        OnEndMission (line 954)
   - OR in a Harmony patch that fires during battle (especially
     CrestPlayerInvincibleDamageClamp on every Mission.RegisterBlow).

Next session strategy: Option 4 -- build a separate Bannerlord.
CrestTactics module. .bak stays deployed for the existing CREST
features. The new module overrides spot orders without touching
the broken CrestBattleConvergenceLogic.cs source. See the new
folder C:\dev\bannerlord\Bannerlord.CrestTactics\ for the project
scaffold.
