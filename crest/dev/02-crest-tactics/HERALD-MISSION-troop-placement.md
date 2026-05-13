# HERALD mission: fix troop placement, formations, and battle locations

Status: in progress (this is HERALD's primary objective right now;
takes priority over track 01 polish).

## The problem (in plain English)

   1. UNITS SPAWN SCATTERED AROUND THE MAP.  Instead of all of side A
      starting at one location and all of side B at another, agents
      from the same party land at multiple disjoint spots.

   2. CAVALRY BEHAVES CORRECTLY.  Cav formations form up at their
      anchor and execute orders (Y.34 anchor placement is doing its
      job for cav).

   3. INFANTRY FORMS BUT DOES NOT MOVE.  Inf formations get assigned
      to the right spot, agents arrange themselves into the formation
      shape, but the formation never receives a movement order it
      acts on. Engine MovementOrder shows StandStill or no order.

   4. ARCHERS DONT FORM AT ALL.  Arch formations are created (slot
      indices reserved) but agents do not get attached to them, so
      there is no formation to give orders to.

In Y.42 cycle terms (per START.md log signature reference):

   Y.42 [side.idx] cav: units=N pos=(x,y) ... engineMove=Charge       <- works
   Y.42 [side.idx] inf: units=N pos=(x,y) ... engineMove=StandStill   <- broken
   Y.42 [side.idx] arch: units=0 pos=(0,0) ... engineMove=NULL        <- broken

## Why this matters

The whole spot architecture (Y.59 / Y.60 / Y.65 / Y.66 / Y.67) exists
to produce Total-War-style mass battles where many parties spawn at
many anchors and execute coordinated tactics. Cav working alone is
not enough -- the player gets lopsided fights where one branch of the
army works and the other two are tactically inert.

## Hypotheses (in priority order)

  H1.  TryAutoDelegateAgent gating.  Y.42c removed the playerteam gate
       so enemy formations get behaviors. But there may be a class-
       specific gate (e.g. only attaches to Inf if Cav is already
       attached) that is silently dropping Arch.

  H2.  AttachAndSetWeight<T> timing.  The manual weight-set fires
       post-Captain. If the Captain assignment is failing for Arch
       formations specifically (e.g. no archer hero in pool), no
       weights ever land, so the formation is "attached but inert" --
       same disease as before Y.36c, but limited to one class.

  H3.  Spot-class assignment.  Y.60b routes agents by class to the
       formation reserved for that class (Inf=slot N, Arch=slot N+1,
       Cav=slot N+2). If the routing is wrong (e.g. all archers route
       to the Cav slot because of an off-by-one), Arch ends up with
       0 agents and Cav ends up doing double duty.

  H4.  Anchor placement for arch.  Y.34 places Inf at base, Arch 12m
       back, Cav 18m to the right. If Arch's anchor is somehow being
       placed at the same point as Inf (e.g. perpendicular vector zero
       when the lord party is facing exactly along an axis), the
       agents pile up at one spot but cant arrange because they think
       they are already "at" the formation position.

  H5.  Inf MovementOrder never re-asserted.  The 3s re-assert pump in
       OnMissionTick re-applies ArrangementOrder + FacingOrder. After
       the initial-hold window, MovementOrder also gets re-applied
       -- but if the initial-hold timer is wrong for Inf (or never
       expires), MovementOrder stays unset.

## Diagnostic plan -- the next 5 battles

For each battle, the agent will look at the postmortem digest and
the runtime.log Y.42 lines for these specific signals:

   Battle 1 (baseline)        confirm the symptoms reproduce on a
                              fresh battle. Get exact arch units
                              count + inf engineMove value.

   Battle 2 (Arch routing)    add a one-shot Y.60b log line that
                              dumps the class -> slot routing decision
                              for every spawned agent for the first
                              60 sec. Look for off-by-one or class
                              mismatches.

   Battle 3 (TryAutoDelegate) instrument TryAutoDelegateAgent to log
                              every entry with formation slot index +
                              class + agent count + Captain status.
                              Look for "skipped because Captain null"
                              spam on Arch.

   Battle 4 (initial-hold)    log the per-formation initial-hold
                              timer for the first 30 sec. See if Inf
                              ever exits the hold window.

   Battle 5 (anchor sanity)   add a one-shot Y.34 log dump of the
                              three anchors as 2D points + the
                              perpendicular vector used for Cav. Look
                              for arch == inf coords.

After battle 5 we should have enough data to identify the root cause
without further instrumentation.

## What HERALD will deliver

  - A series of small, gated diagnostic patches (CrestVerbose.cs
    additions) that add the per-battle log lines above. Each gated
    on a fine-grained config flag (e.g. EnableTroopPlacementProbe1)
    so they can be turned off after the diagnosis lands.
  - One root-cause patch per battle's findings.
  - A new sim scenario per fix that reproduces the original symptom
    against the synthetic harness, so the regression doesnt come
    back silently.
  - A two-line update to the Y.65/Y.66/Y.67 phase index in START.md
    when the symptoms are gone.

## What HERALD will NOT do (out of scope for this mission)

  - Reorganize the spot architecture itself.
  - Add new tactical variants (Circle, Wedge, etc.).
  - Touch the campaign-side Battle Convergence party-discovery code.
  - Touch any non-Y.4x / non-Y.6x phase code.

## Acceptance criteria

  - Five consecutive battles show:
      Y.42 [side.idx] inf: units > 0  AND  engineMove != StandStill
      Y.42 [side.idx] arch: units > 0  AND  engineMove != NULL
      Y.42 [side.idx] cav: continues to work as today
  - The sim regression suite remains 0 failures.
  - No new crashreports caused by the changes.

## Where to start

  - Read CODE_INDEX.md for the symbol table.
  - Read CrestBattleConvergenceLogic.cs for the spot orchestration
    and TryAutoDelegateAgent code.
  - Read CrestSpot.cs for the per-spot state.
  - Read CrestFormationRules.cs for the Y.54 override decisions.
  - Run Crest.ps1 -Mode Doctor first to confirm the source tree is
    intact before any change.
