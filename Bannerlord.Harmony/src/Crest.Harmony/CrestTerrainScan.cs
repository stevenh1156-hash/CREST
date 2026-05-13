using System;
using System.Collections.Generic;
using System.Linq;

using TaleWorlds.Library;
using TaleWorlds.MountAndBlade;

namespace Bannerlord.Harmony;

/// <summary>
/// Y.59: scan the battlefield's heightmap at mission start and pick
/// tactically-meaningful spawn spots dynamically based on terrain features.
///
/// <para>
/// Goal: replace the static 2-anchors-per-side spawn model with a dynamic
/// per-map plan. Lords spawn at hills, ridges, flanks, or rear positions
/// that actually exist on this specific battlefield. Class-aware fill
/// routes archers to overlook spots, cav to flanks, inf to front.
/// </para>
///
/// <para>
/// The scan happens once at mission start (~100-200ms). It samples the
/// heightmap on a 40x40 grid centered on battle center, finds local maxima
/// (hills) and large flats (deployment zones), scores candidates by
/// terrain advantage + side allegiance + spread, and picks 4-8 spots per
/// side with target capacity ~1000 troops/side.
/// </para>
///
/// <para>
/// Fallbacks are explicit: if the scan returns garbage on >50% of samples,
/// or if fewer than 4 viable candidates score above threshold, we fall
/// back to a fixed ring template. The spawn pipeline always has 4-8
/// usable spots no matter how unusual the map is.
/// </para>
/// </summary>
public static class CrestTerrainScan
{
    private const string Source = "CrestTerrainScan";

    // -- algorithm tunables --

    /// <summary>Half-width of the sampled square, in world meters.</summary>
    private const float ScanRadiusM = 400f;
    /// <summary>Grid resolution. 40 = 20m sample spacing across 800m square.</summary>
    private const int   GridN = 40;
    /// <summary>Min spread between picked spots (so we don't cluster on one hill).</summary>
    private const float MinSpotDistanceM = 50f;
    /// <summary>If fewer than this many candidates score above threshold, fall back.</summary>
    private const int   MinSpotsBeforeFallback = 4;
    /// <summary>Cap to avoid eating too many of the engine's 24 formation slots.</summary>
    private const int   MaxSpotsPerSide = 8;
    /// <summary>Target total per-side troop capacity. Spot caps are normalized to this.</summary>
    private const int   TargetCapacityPerSide = 1000;
    /// <summary>A height delta of this magnitude (m) qualifies a candidate as "hill".</summary>
    private const float HillHeightThreshold = 4f;
    /// <summary>If max height delta across all samples is below this, map is "flat" -> ring fallback.</summary>
    private const float FlatMapThreshold = 3f;

    /// <summary>
    /// Run the scan and pick spots for both sides. Always returns a list
    /// of 4-8 spots per side; falls back to ring template if topography
    /// scan fails.
    /// </summary>
    /// <param name="mission">live Mission for Scene access</param>
    /// <param name="battleCenter">midpoint between defender + attacker flee zones</param>
    /// <param name="allyFleeZones">defender or attacker flee zones depending on player side</param>
    /// <param name="enemyFleeZones">opposing flee zones</param>
    /// <returns>(allySpots, enemySpots) ready to be assigned formation indices</returns>
    public static (List<CrestSpot> ally, List<CrestSpot> enemy) ScanAndPickSpots(
        Mission mission,
        Vec3 battleCenter,
        IList<Vec3> allyFleeZones,
        IList<Vec3> enemyFleeZones)
    {
        try
        {
            // 1. Sample heightmap on a grid around battle center.
            var samples = SampleHeightmap(mission, battleCenter);
            if (samples.Count < (GridN * GridN) / 2)
            {
                CrestDiag.Log(Source,
                    $"Y.59 terrain-scan: only {samples.Count}/{GridN*GridN} valid samples -> fallback to ring");
                return RingFallback(battleCenter, allyFleeZones, enemyFleeZones);
            }

            // 2. Compute terrain summary -- hills, flats, max height delta.
            var summary = AnalyzeSamples(samples, battleCenter);
            CrestDiag.Log(Source,
                $"Y.59 terrain-scan: samples={samples.Count} maxDelta={summary.MaxHeightDelta:F1}m " +
                $"hills={summary.Hills.Count} flats={summary.Flats.Count}");

            if (summary.MaxHeightDelta < FlatMapThreshold)
            {
                CrestDiag.Log(Source,
                    $"Y.59 terrain-scan: flat map detected (maxDelta < {FlatMapThreshold}m) -> ring fallback");
                return RingFallback(battleCenter, allyFleeZones, enemyFleeZones);
            }

            // 3. Establish side-axis from ally vs enemy flee zones.
            var sideAxis = ComputeSideAxis(allyFleeZones, enemyFleeZones, battleCenter);

            // 4. Build candidates from terrain features. Each candidate gets a
            //    score; we pick the top N per side.
            var candidates = BuildCandidates(summary, samples, battleCenter, sideAxis);

            // 5. Pick per-side, then assign roles + capacities.
            var allySpots  = PickForSide(candidates, isEnemy: false, sideAxis, battleCenter);
            var enemySpots = PickForSide(candidates, isEnemy: true,  sideAxis, battleCenter);

            if (allySpots.Count < MinSpotsBeforeFallback || enemySpots.Count < MinSpotsBeforeFallback)
            {
                CrestDiag.Log(Source,
                    $"Y.59 terrain-scan: insufficient candidates (ally={allySpots.Count}, enemy={enemySpots.Count}) -> ring fallback");
                return RingFallback(battleCenter, allyFleeZones, enemyFleeZones);
            }

            // 6. Normalize capacities so each side sums to ~TargetCapacityPerSide.
            NormalizeCapacities(allySpots,  TargetCapacityPerSide);
            NormalizeCapacities(enemySpots, TargetCapacityPerSide);

            // Y.65: scan for structures (houses, walls, towers) and re-score
            // spots near them. Spots adjacent to structures get a TerrainTag
            // boost and may flip role to Anchor (defensive). If structure
            // detection fails (no entities, reflection error), this is a
            // graceful no-op and the original picks stand.
            try
            {
                var structures = ProbeStructures(mission);
                if (structures.Count > 0)
                {
                    ApplyStructureProximity(allySpots,  structures);
                    ApplyStructureProximity(enemySpots, structures);
                }
                CrestDiag.Log(Source, $"Y.65 structure-scan: found {structures.Count} structures");
            }
            catch (Exception ex) { CrestDiag.LogCaught(Source, "Y.65 structure scan", ex); }

            // 7. Log the battle plan for diag visibility.
            LogBattlePlan(allySpots,  "ally");
            LogBattlePlan(enemySpots, "enemy");

            return (allySpots, enemySpots);
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "ScanAndPickSpots", ex);
            return RingFallback(battleCenter, allyFleeZones, enemyFleeZones);
        }
    }

    // -- 1. heightmap sampling ----------------------------------------------

    /// <summary>One height sample. World-space (x,y) plus terrain z.</summary>
    private struct HeightSample
    {
        public float X;
        public float Y;
        public float Z;
    }

    private static List<HeightSample> SampleHeightmap(Mission mission, Vec3 center)
    {
        var samples = new List<HeightSample>(GridN * GridN);
        var scene = mission?.Scene;
        if (scene == null) return samples;

        float step = (2f * ScanRadiusM) / GridN;
        for (int gx = 0; gx < GridN; gx++)
        {
            for (int gy = 0; gy < GridN; gy++)
            {
                float wx = center.x - ScanRadiusM + step * gx;
                float wy = center.y - ScanRadiusM + step * gy;
                float wz = center.z;
                try
                {
                    var v2 = new Vec2(wx, wy);
                    // v1.4.x signature: float GetGroundHeightAtPosition(Vec3 position, BodyFlags ...)
                    // We try multiple shapes via reflection-friendly approach but stick
                    // with the typed call here for net472 compatibility.
                    wz = scene.GetGroundHeightAtPosition(new Vec3(wx, wy, center.z + 200f));
                    if (float.IsNaN(wz) || float.IsInfinity(wz)) continue;
                    if (wz < center.z - 60f || wz > center.z + 200f) continue; // off-map / invalid
                }
                catch { continue; }
                samples.Add(new HeightSample { X = wx, Y = wy, Z = wz });
            }
        }
        return samples;
    }

    // -- 2. terrain summary -------------------------------------------------

    private sealed class TerrainSummary
    {
        public float MaxHeightDelta;
        public List<HeightSample> Hills = new();
        public List<HeightSample> Flats = new();
    }

    /// <summary>Find local maxima (hills) and low-variance regions (flats).</summary>
    private static TerrainSummary AnalyzeSamples(List<HeightSample> samples, Vec3 center)
    {
        var summary = new TerrainSummary();
        if (samples.Count == 0) return summary;

        // Track max height delta vs center.
        foreach (var s in samples)
        {
            float delta = s.Z - center.z;
            if (Math.Abs(delta) > summary.MaxHeightDelta) summary.MaxHeightDelta = Math.Abs(delta);
        }

        // Local maxima detection. Use STRICT inequality to avoid false maxima
        // on dead-flat plateaus where many adjacent samples have identical Z.
        // A sample qualifies if no neighbor within radius is strictly higher.
        var rawMaxima = new List<HeightSample>();
        const float NeighborRadius = 50f;
        foreach (var s in samples)
        {
            bool isMax = true;
            foreach (var n in samples)
            {
                if (ReferenceEquals(s, n)) continue;
                float dx = n.X - s.X, dy = n.Y - s.Y;
                float d2 = dx*dx + dy*dy;
                if (d2 > NeighborRadius * NeighborRadius) continue;
                if (n.Z > s.Z) { isMax = false; break; }
            }
            if (!isMax) continue;
            if (s.Z - center.z < HillHeightThreshold) continue;
            rawMaxima.Add(s);
        }

        // Plateau dedup: two maxima are the SAME tactical feature if they are
        // within ~100m AND within 4m elevation of each other (i.e. on the same
        // broad flat-topped hill). This stops the picker from selecting 5
        // different points on one plateau as if they were 5 separate hills.
        // Wider radius (100m) catches plateaus; tight elevation gate (4m) keeps
        // genuinely different peaks separate even when they're nearby.
        const float PlateauRadius   = 100f;
        const float PlateauHeightTol = 4f;
        rawMaxima.Sort((a, b) => b.Z.CompareTo(a.Z));
        foreach (var m in rawMaxima)
        {
            bool sameAsExisting = summary.Hills.Any(h =>
            {
                float dx = h.X - m.X, dy = h.Y - m.Y;
                float d2 = dx * dx + dy * dy;
                bool spatiallyClose = d2 < PlateauRadius * PlateauRadius;
                bool elevationClose = Math.Abs(h.Z - m.Z) < PlateauHeightTol;
                return spatiallyClose && elevationClose;
            });
            if (!sameAsExisting) summary.Hills.Add(m);
        }

        // Flats -- pick the largest connected region of similar-height samples.
        // Simplification: just record samples within 1.5m of center height as
        // candidate flats. The flat-region structure is implicit in spread.
        foreach (var s in samples)
        {
            if (Math.Abs(s.Z - center.z) < 1.5f) summary.Flats.Add(s);
        }

        return summary;
    }

    // -- 3. side axis -------------------------------------------------------

    private struct SideAxis
    {
        public Vec3 AllyAnchor;
        public Vec3 EnemyAnchor;
        /// <summary>Direction from ally to enemy (normalized).</summary>
        public Vec3 ToEnemyDir;
    }

    private static SideAxis ComputeSideAxis(IList<Vec3> ally, IList<Vec3> enemy, Vec3 center)
    {
        Vec3 a = ally.Count   > 0 ? Average(ally)   : new Vec3(center.x, center.y - 100f, center.z);
        Vec3 e = enemy.Count  > 0 ? Average(enemy)  : new Vec3(center.x, center.y + 100f, center.z);
        Vec3 dir = new Vec3(e.x - a.x, e.y - a.y, 0f);
        float len = (float)Math.Sqrt(dir.x * dir.x + dir.y * dir.y);
        if (len > 0.001f) { dir.x /= len; dir.y /= len; }
        return new SideAxis { AllyAnchor = a, EnemyAnchor = e, ToEnemyDir = dir };
    }

    private static Vec3 Average(IList<Vec3> v)
    {
        float x = 0, y = 0, z = 0;
        foreach (var p in v) { x += p.x; y += p.y; z += p.z; }
        return new Vec3(x / v.Count, y / v.Count, z / v.Count);
    }

    // -- 4. candidate construction ------------------------------------------

    private struct Candidate
    {
        public Vec3   Pos;
        public float HeightDelta;
        public string Tag;          // "hill" | "flat" | "ridge"
        public float Score;
        public bool  IsEnemySide;
        /// <summary>Footprint flatness around this candidate -- counts samples within 1.5m of its height in 20m radius. Used for capacity calc.</summary>
        public int   FootprintCount;
    }

    private static List<Candidate> BuildCandidates(
        TerrainSummary summary, List<HeightSample> allSamples,
        Vec3 center, SideAxis axis)
    {
        var list = new List<Candidate>();

        // Hills -- always strong candidates (good for archers / overlook).
        foreach (var h in summary.Hills)
        {
            list.Add(new Candidate
            {
                Pos = new Vec3(h.X, h.Y, h.Z),
                HeightDelta = h.Z - center.z,
                Tag = "hill",
                FootprintCount = CountFlatNeighbors(h, allSamples, 20f, 2.5f),
                IsEnemySide = ProjectOntoAxis(h.X, h.Y, axis) > 0f,
            });
        }

        // Flats -- a few well-spread flat candidates per side.
        // Subsample every 4th flat to avoid O(N^2) scoring; that gives ~50-100
        // flats max which is plenty.
        var flatSubsample = summary.Flats.Where((_, i) => i % 4 == 0).ToList();
        foreach (var f in flatSubsample)
        {
            list.Add(new Candidate
            {
                Pos = new Vec3(f.X, f.Y, f.Z),
                HeightDelta = f.Z - center.z,
                Tag = "flat",
                FootprintCount = CountFlatNeighbors(f, allSamples, 20f, 1.5f),
                IsEnemySide = ProjectOntoAxis(f.X, f.Y, axis) > 0f,
            });
        }

        // Score every candidate. Height bonus is CAPPED so other factors
        // aren't dominated on extreme-terrain maps (e.g. a 180m-elevation
        // mountain pass would otherwise make every score ~180+, drowning
        // center/spread/diversity entirely). Cap at 25 means a flat-ish
        // hill at +5m and a peak at +180m score similarly on terrain alone;
        // the picker's job becomes spreading them tactically, not just
        // sorting by altitude.
        for (int i = 0; i < list.Count; i++)
        {
            var c = list[i];
            float terrainScore = Math.Min(c.HeightDelta, 25f);                   // capped
            float centerScore  = -Math.Abs(Distance(c.Pos, center) - 200f) * 0.05f; // peak ~200m
            // (sideScore added later per-side.)
            c.Score = terrainScore + centerScore;
            list[i] = c;
        }
        return list;
    }

    private static float ProjectOntoAxis(float x, float y, SideAxis axis)
    {
        // 0 = at battle center; positive = toward enemy; negative = toward ally.
        float dx = x - axis.AllyAnchor.x;
        float dy = y - axis.AllyAnchor.y;
        float t  = dx * axis.ToEnemyDir.x + dy * axis.ToEnemyDir.y;
        // Battle midline = halfway between ally and enemy anchor.
        float midline = 0.5f * Distance(axis.AllyAnchor, axis.EnemyAnchor);
        return t - midline;
    }

    private static int CountFlatNeighbors(HeightSample center, List<HeightSample> all, float radius, float heightTol)
    {
        int n = 0;
        float r2 = radius * radius;
        foreach (var s in all)
        {
            float dx = s.X - center.X, dy = s.Y - center.Y;
            if (dx * dx + dy * dy > r2) continue;
            if (Math.Abs(s.Z - center.Z) <= heightTol) n++;
        }
        return n;
    }

    private static float Distance(Vec3 a, Vec3 b)
    {
        float dx = a.x - b.x, dy = a.y - b.y;
        return (float)Math.Sqrt(dx * dx + dy * dy);
    }

    // -- 5. per-side picking + role assignment ------------------------------

    private static List<CrestSpot> PickForSide(List<Candidate> candidates, bool isEnemy, SideAxis axis, Vec3 center)
    {
        // Filter to own-side candidates and adjust score for own-side bias.
        float sideSign = isEnemy ? +1f : -1f;
        var ownSide = candidates
            .Where(c => c.IsEnemySide == isEnemy)
            .Select(c => { c.Score += 0f; return c; })  // (already side-filtered)
            .OrderByDescending(c => c.Score)
            .ToList();

        var picked = new List<CrestSpot>();

        // Greedy spread-aware pick.
        foreach (var c in ownSide)
        {
            if (picked.Count >= MaxSpotsPerSide) break;
            bool tooClose = picked.Any(p =>
            {
                float dx = p.Anchor.x - c.Pos.x, dy = p.Anchor.y - c.Pos.y;
                return dx * dx + dy * dy < MinSpotDistanceM * MinSpotDistanceM;
            });
            if (tooClose) continue;

            picked.Add(new CrestSpot
            {
                Anchor      = c.Pos,
                HeightDelta = c.HeightDelta,
                TerrainTag  = c.Tag,
                PickScore   = c.Score,
                IsEnemySpot = isEnemy,
                // Capacity from footprint -- normalized later.
                Capacity    = Math.Max(30, 30 + c.FootprintCount * 2),
            });
        }

        // Assign roles. We label the picks AFTER picking, based on relative
        // position + height profile. Order matters so we tag the best-fitting
        // candidate for each role first.
        AssignRoles(picked, axis, center, isEnemy);

        return picked;
    }

    private static void AssignRoles(List<CrestSpot> spots, SideAxis axis, Vec3 center, bool isEnemy)
    {
        if (spots.Count == 0) return;

        // Lateral axis: perpendicular to ToEnemyDir. (px, py) -> swing left/right.
        float ax = axis.ToEnemyDir.x, ay = axis.ToEnemyDir.y;
        // perpendicular (CCW 90) = (-ay, ax) -- "right" from ally's facing
        float rx = -ay, ry = ax;
        // (Mirror for enemy: their "right" is ally's "left".)
        if (isEnemy) { rx = -rx; ry = -ry; }

        // Score each spot for each role; pick best per role.
        // Build sort keys.
        var byHeight       = spots.OrderByDescending(s => s.HeightDelta).ToList();
        var byCenter       = spots.OrderBy(s => Distance(s.Anchor, center)).ToList();
        var byLeftAmount   = spots.OrderByDescending(s => -((s.Anchor.x - center.x) * rx + (s.Anchor.y - center.y) * ry)).ToList();
        var byRightAmount  = spots.OrderByDescending(s => +((s.Anchor.x - center.x) * rx + (s.Anchor.y - center.y) * ry)).ToList();
        var byCenterDesc   = spots.OrderByDescending(s => Distance(s.Anchor, center)).ToList();

        var assigned = new HashSet<CrestSpot>();
        void Assign(CrestSpot s, SpotRole role)
        {
            if (assigned.Contains(s)) return;
            s.Role = role;
            s.ClassPreference = role switch
            {
                SpotRole.Overlook   => ClassPref.ArcherPreferred,
                SpotRole.FlankLeft  => ClassPref.CavalryPreferred,
                SpotRole.FlankRight => ClassPref.CavalryPreferred,
                SpotRole.Front      => ClassPref.InfantryPreferred,
                SpotRole.Anchor     => ClassPref.InfantryPreferred,
                SpotRole.Reserve    => ClassPref.Mixed,
                _                   => ClassPref.Mixed,
            };
            assigned.Add(s);
        }

        // Primary role assignment -- one of each.
        var bestHill = byHeight.FirstOrDefault();
        if (bestHill != null && bestHill.HeightDelta >= HillHeightThreshold) Assign(bestHill, SpotRole.Overlook);
        var front = byCenter.FirstOrDefault(s => !assigned.Contains(s));
        if (front != null) Assign(front, SpotRole.Front);
        var flankL = byLeftAmount.FirstOrDefault(s => !assigned.Contains(s));
        if (flankL != null) Assign(flankL, SpotRole.FlankLeft);
        var flankR = byRightAmount.FirstOrDefault(s => !assigned.Contains(s));
        if (flankR != null) Assign(flankR, SpotRole.FlankRight);
        var reserve = byCenterDesc.FirstOrDefault(s => !assigned.Contains(s));
        if (reserve != null) Assign(reserve, SpotRole.Reserve);

        // Leftover assignment based on actual position. Avoids the "everything
        // becomes Anchor" sprawl when terrain offers many candidates.
        // Each leftover spot is reclassified by its strongest geometric feature:
        //   - elevation >= 5m above center  -> additional Overlook
        //   - lateral distance >= 80m       -> additional FlankLeft/FlankRight
        //   - forward distance < -50m       -> additional Reserve (deeper rear)
        //   - close to map edge (>250m from center on one axis) -> Anchor (genuine barrier-anchored)
        //   - otherwise                     -> additional Front (main line)
        foreach (var s in spots)
        {
            if (assigned.Contains(s)) continue;
            float dx = s.Anchor.x - center.x;
            float dy = s.Anchor.y - center.y;
            float lateral = dx * rx + dy * ry;             // signed: +right, -left
            float forward = dx * ax + dy * ay;             // signed: +toward enemy, -toward own rear
            float distFromCenter = (float)Math.Sqrt(dx*dx + dy*dy);
            // Enemy spots: from their POV, "own rear" is opposite direction from ally axis.
            float ownRear = isEnemy ? +forward : -forward;

            if (s.HeightDelta >= 5f)
                Assign(s, SpotRole.Overlook);
            else if (Math.Abs(lateral) >= 80f)
                Assign(s, lateral >= 0 ? SpotRole.FlankRight : SpotRole.FlankLeft);
            else if (ownRear >= 50f)
                Assign(s, SpotRole.Reserve);
            else if (distFromCenter >= 250f)
                Assign(s, SpotRole.Anchor);   // genuine barrier-anchored
            else
                Assign(s, SpotRole.Front);    // mid-elevation, central-ish -> main line
        }
    }

    // -- 6. capacity normalization ------------------------------------------

    private static void NormalizeCapacities(List<CrestSpot> spots, int target)
    {
        if (spots.Count == 0) return;
        long sum = spots.Sum(s => (long)s.Capacity);
        if (sum <= 0) { foreach (var s in spots) s.Capacity = target / Math.Max(1, spots.Count); return; }
        float scale = target / (float)sum;
        foreach (var s in spots) s.Capacity = Math.Max(20, (int)(s.Capacity * scale));
    }

    // -- 7. battle plan logging ---------------------------------------------

    private static void LogBattlePlan(List<CrestSpot> spots, string sideTag)
    {
        CrestDiag.Log(Source,
            $"Y.59 battle-plan: {sideTag} side, {spots.Count} spots picked");
        for (int i = 0; i < spots.Count; i++)
        {
            var s = spots[i];
            CrestDiag.Log(Source,
                $"  {sideTag}.spot[{i}] {s.Role,-12} pos=({s.Anchor.x:F1},{s.Anchor.y:F1}) " +
                $"cap={s.Capacity,-4} elev={s.HeightDelta:+0.0;-0.0;0.0}m " +
                $"tag={s.TerrainTag} pref={s.ClassPreference} score={s.PickScore:F2}");
        }
    }

    // -- ring fallback: 6 evenly-spaced points at 200m for each side --------

    private static (List<CrestSpot> ally, List<CrestSpot> enemy) RingFallback(
        Vec3 center, IList<Vec3> ally, IList<Vec3> enemy)
    {
        var allyAnchor  = ally.Count  > 0 ? Average(ally)  : new Vec3(center.x, center.y - 100f, center.z);
        var enemyAnchor = enemy.Count > 0 ? Average(enemy) : new Vec3(center.x, center.y + 100f, center.z);

        var allyList  = BuildRingForSide(center, allyAnchor,  isEnemy: false);
        var enemyList = BuildRingForSide(center, enemyAnchor, isEnemy: true);

        NormalizeCapacities(allyList,  TargetCapacityPerSide);
        NormalizeCapacities(enemyList, TargetCapacityPerSide);

        LogBattlePlan(allyList,  "ally (RING-FALLBACK)");
        LogBattlePlan(enemyList, "enemy (RING-FALLBACK)");
        return (allyList, enemyList);
    }

    private static List<CrestSpot> BuildRingForSide(Vec3 center, Vec3 sideAnchor, bool isEnemy)
    {
        // 6 spots in a half-arc on this side, plus one reserve far rear.
        var dir = new Vec3(sideAnchor.x - center.x, sideAnchor.y - center.y, 0f);
        float dlen = (float)Math.Sqrt(dir.x * dir.x + dir.y * dir.y);
        if (dlen < 0.001f) { dir.x = 0; dir.y = isEnemy ? 1 : -1; dlen = 1; }
        else { dir.x /= dlen; dir.y /= dlen; }
        // Perpendicular axis -- "right" from this side facing center.
        float rx = -dir.y, ry = dir.x;

        var list = new List<CrestSpot>();
        // 5 forward arc points + 1 reserve = 6 total.
        var forwardOffsets = new (float along, float perp, SpotRole role)[]
        {
            ( 1.0f,  0.0f, SpotRole.Front),       // dead-front toward center
            ( 0.7f, +0.7f, SpotRole.FlankRight),  // forward-right
            ( 0.7f, -0.7f, SpotRole.FlankLeft),   // forward-left
            ( 0.4f, +0.9f, SpotRole.Anchor),      // far right (edge)
            ( 0.4f, -0.9f, SpotRole.Anchor),      // far left  (edge)
        };
        const float RingRadiusM = 150f;
        foreach (var off in forwardOffsets)
        {
            float ox = sideAnchor.x - dir.x * RingRadiusM * off.along + rx * RingRadiusM * off.perp;
            float oy = sideAnchor.y - dir.y * RingRadiusM * off.along + ry * RingRadiusM * off.perp;
            list.Add(new CrestSpot
            {
                Anchor      = new Vec3(ox, oy, center.z),
                Capacity    = 100,
                Role        = off.role,
                ClassPreference = ClassPrefForRole(off.role),
                HeightDelta = 0f,
                TerrainTag  = "ring",
                IsEnemySpot = isEnemy,
            });
        }
        // Reserve -- on own side, opposite direction from center.
        list.Add(new CrestSpot
        {
            Anchor      = new Vec3(sideAnchor.x + dir.x * 50f, sideAnchor.y + dir.y * 50f, center.z),
            Capacity    = 100,
            Role        = SpotRole.Reserve,
            ClassPreference = ClassPref.Mixed,
            HeightDelta = 0f,
            TerrainTag  = "ring-reserve",
            IsEnemySpot = isEnemy,
        });
        return list;
    }

    private static ClassPref ClassPrefForRole(SpotRole r) => r switch
    {
        SpotRole.Overlook   => ClassPref.ArcherPreferred,
        SpotRole.FlankLeft  => ClassPref.CavalryPreferred,
        SpotRole.FlankRight => ClassPref.CavalryPreferred,
        SpotRole.Front      => ClassPref.InfantryPreferred,
        SpotRole.Anchor     => ClassPref.InfantryPreferred,
        SpotRole.Ambush     => ClassPref.Mixed,
        _                   => ClassPref.Mixed,
    };

    // ----------------------------------------------------------------
    // Y.65: structure-proximity scoring (houses, walls, towers).
    // Reflectively probes Scene for tagged entities. First-call discovery
    // dump shows what tags the current map exposes.
    // ----------------------------------------------------------------

    private static bool _structureDiscoveryLogged;

    /// <summary>
    /// Returns a list of structure positions from the scene's tagged
    /// entities. Best-effort -- returns empty list on any reflection
    /// failure or if the scene has no recognizable structure tags.
    /// </summary>
    private static List<Vec3> ProbeStructures(Mission mission)
    {
        var positions = new List<Vec3>();
        if (mission?.Scene == null) return positions;
        try
        {
            var scene = mission.Scene;
            var sceneType = scene.GetType();

            // Once-per-session discovery -- dump methods, properties, and the
            // root-entity count so we have full visibility into the API
            // surface that's actually available in this build.
            if (!_structureDiscoveryLogged)
            {
                _structureDiscoveryLogged = true;
                try
                {
                    var allMethods = string.Join(", ",
                        sceneType.GetMethods()
                                 .Where(m => !m.IsSpecialName || m.Name.StartsWith("get_"))
                                 .Select(m => m.Name + "(" + m.GetParameters().Length + ")")
                                 .Distinct());
                    var allProps = string.Join(", ", sceneType.GetProperties().Select(p => p.Name));
                    CrestDiag.Log(Source, $"Y.65 scene type:    {sceneType.FullName}");
                    CrestDiag.Log(Source, $"Y.65 scene methods: {allMethods}");
                    CrestDiag.Log(Source, $"Y.65 scene props:   {allProps}");
                    try
                    {
                        var rec = sceneType.GetProperty("RootEntityCount")?.GetValue(scene);
                        CrestDiag.Log(Source, $"Y.65 RootEntityCount: {rec}");
                    }
                    catch (Exception rex) { CrestDiag.Log(Source, "Y.65 RootEntityCount probe failed: " + rex.Message); }
                }
                catch { }
            }

            // Strategy A: walk the entire entity tree starting from any root
            // we can find. Bannerlord's Scene exposes the count of root
            // entities; iterate via reflection-friendly accessors.
            int walked = 0, examined = 0;
            try
            {
                walked = WalkEntityTree(scene, sceneType, positions, ref examined);
            }
            catch (Exception wex) { CrestDiag.Log(Source, "Y.65 tree walk failed: " + wex.Message); }

            // Strategy B fallback: probe common structure tags via the
            // PLURAL FindEntitiesWithTag(string) method (returns enumerable).
            // Use only when the tree walk yielded nothing.
            if (positions.Count == 0)
            {
                try
                {
                    var findEntitiesByTag = sceneType.GetMethod("FindEntitiesWithTag", new[] { typeof(string) });
                    if (findEntitiesByTag != null)
                    {
                        var commonTags = new[] { "house", "wall", "tower", "barn", "gate",
                                                 "village_house", "structure", "ruin", "stone_wall",
                                                 "wooden_wall", "watchtower" };
                        foreach (var tag in commonTags)
                        {
                            try
                            {
                                var rv = findEntitiesByTag.Invoke(scene, new object[] { tag });
                                if (rv is System.Collections.IEnumerable e)
                                {
                                    foreach (var ent in e) if (ent != null) AppendEntityPosition(ent, positions);
                                }
                            }
                            catch { }
                        }
                    }
                }
                catch (Exception tex) { CrestDiag.Log(Source, "Y.65 tag probe failed: " + tex.Message); }
            }

            CrestDiag.Log(Source,
                $"Y.65 probe: examined={examined} structures-found={positions.Count} via=" +
                (walked > 0 ? "tree" : "tag-fallback"));
        }
        catch (Exception ex)
        {
            try { CrestDiag.Log(Source, "Y.65 ProbeStructures top-level failed: " + ex.Message); } catch { }
        }
        return positions;
    }

    /// <summary>
    /// Walks the scene's entity tree and adds positions of any entity
    /// whose Name matches structure keywords. Returns the number of
    /// structure-shaped entities added.
    ///
    /// In Bannerlord 1.4.3 (verified by Y.65 v2 discovery dump on real
    /// scene), the canonical APIs are:
    ///   void Scene.GetEntities(List&lt;GameEntity&gt;)       -- all entities
    ///   void Scene.GetRootEntities(List&lt;GameEntity&gt;)   -- root entities
    ///
    /// We invoke them via reflection so this file doesn't have a hard
    /// dependency on TaleWorlds.Engine, and so we can also fall back
    /// to other shapes if a future version renames things.
    /// </summary>
    private static int WalkEntityTree(object scene, Type sceneType, List<Vec3> positions, ref int examined)
    {
        // Find a method by name that takes exactly one List-shaped parameter.
        // Prefer GetEntities (full set) over GetRootEntities, since structures
        // can be nested under any root.
        var preferredOrder = new[] { "GetEntities", "GetRootEntities", "GetAllEntitiesWithScriptComponent" };
        System.Reflection.MethodInfo? methodToUse = null;
        Type? listElementType = null;
        Type? paramType = null;
        bool isByRef = false;

        // v5: accept ANY shape -- strip the IsGenericType filter, log
        // every candidate's param type so future runs can be tuned, and
        // handle by-ref + array param shapes too.
        foreach (var name in preferredOrder)
        {
            foreach (var m in sceneType.GetMethods())
            {
                if (m.Name != name) continue;
                var ps = m.GetParameters();
                if (ps.Length != 1) continue;
                var rawPt = ps[0].ParameterType;
                CrestDiag.Log(Source, $"Y.65 candidate: {name}  paramType={rawPt.FullName}  isByRef={rawPt.IsByRef}  isArray={rawPt.IsArray}  isGeneric={rawPt.IsGenericType}");

                // Unwrap by-ref (`out List<T>` or `ref MBList<T>`).
                var pt = rawPt;
                if (pt.IsByRef) { pt = pt.GetElementType()!; isByRef = true; } else { isByRef = false; }

                // Determine element type.
                Type? elemType = null;
                if (pt.IsArray) elemType = pt.GetElementType();
                else if (pt.IsGenericType) elemType = pt.GetGenericArguments()[0];

                if (elemType == null) continue;

                paramType = pt;
                listElementType = elemType;
                methodToUse = m;
                break;
            }
            if (methodToUse != null) break;
        }

        if (methodToUse == null || listElementType == null || paramType == null)
        {
            CrestDiag.Log(Source, "Y.65 walk: no GetEntities-style method found (after v5 candidate scan -- check candidate logs above)");
            return 0;
        }

        // Build the right object for the param shape.
        object list;
        try
        {
            Type typeToInstantiate;
            if (paramType.IsArray)
            {
                // For an array param we still need a fillable container.
                // Most "GetEntities(out arr)" patterns have the method
                // overwrite the variable; we pass an empty array as
                // initial value and let reflection rebind via the args[].
                typeToInstantiate = paramType;
                list = Array.CreateInstance(listElementType, 0);
            }
            else if (paramType.IsInterface || paramType.IsAbstract)
            {
                typeToInstantiate = typeof(List<>).MakeGenericType(listElementType);
                list = Activator.CreateInstance(typeToInstantiate)!;
            }
            else
            {
                typeToInstantiate = paramType;
                list = Activator.CreateInstance(typeToInstantiate)!;
            }

            CrestDiag.Log(Source, $"Y.65 walk: invoking {methodToUse.Name}  passing={typeToInstantiate.Name}  byRef={isByRef}");

            var args = new object[] { list };
            methodToUse.Invoke(scene, args);

            // For by-ref / out, the method may have rebound args[0].
            if (isByRef) list = args[0];
        }
        catch (Exception lex)
        {
            CrestDiag.Log(Source, "Y.65 walk: invocation failed: " + lex.Message +
                                  "  param=" + paramType.FullName +
                                  "  byRef=" + isByRef);
            return 0;
        }

        // Iterate the populated list -- it implements IEnumerable.
        int found = 0;
        try
        {
            int total = 0;
            if (list is System.Collections.IEnumerable enumerable)
            {
                foreach (var e in enumerable)
                {
                    total++;
                    examined++;
                    if (e == null) continue;
                    if (IsStructureNamed(e))
                    {
                        if (AppendEntityPosition(e, positions)) found++;
                    }
                }
            }
            CrestDiag.Log(Source, $"Y.65 walk: method={methodToUse.Name} returned {total} entities, {found} structures matched");
        }
        catch (Exception iex)
        {
            CrestDiag.Log(Source, "Y.65 walk: enumeration failed: " + iex.Message);
        }
        return found;
    }

    private static bool IsStructureNamed(object entity)
    {
        try
        {
            var et = entity.GetType();
            string name = "";
            try { name = (et.GetProperty("Name")?.GetValue(entity) as string) ?? ""; } catch { }
            if (string.IsNullOrEmpty(name)) return false;
            var lower = name.ToLowerInvariant();
            return lower.Contains("house")  || lower.Contains("wall")  || lower.Contains("tower")
                || lower.Contains("hut")    || lower.Contains("barn")  || lower.Contains("gate")
                || lower.Contains("ruin")   || lower.Contains("structure")
                || lower.Contains("village") || lower.Contains("castle") || lower.Contains("smith");
        }
        catch { return false; }
    }

    /// <summary>
    /// Reads GlobalPosition off an entity (multiple API patterns) and
    /// appends the resulting Vec3 to the list. Returns true on success.
    /// </summary>
    private static bool AppendEntityPosition(object entity, List<Vec3> positions)
    {
        try
        {
            var et = entity.GetType();
            object? posObj = null;
            try { posObj = et.GetProperty("GlobalPosition")?.GetValue(entity); } catch { }
            if (posObj == null)
            {
                try
                {
                    var frame = et.GetMethod("GetGlobalFrame", Type.EmptyTypes)?.Invoke(entity, null);
                    if (frame != null)
                    {
                        var ft = frame.GetType();
                        posObj = ft.GetField("origin")?.GetValue(frame)
                              ?? ft.GetProperty("origin")?.GetValue(frame);
                    }
                }
                catch { }
            }
            if (posObj == null) return false;

            var pt = posObj.GetType();
            var fx = pt.GetField("x") ?? pt.GetField("X");
            var fy = pt.GetField("y") ?? pt.GetField("Y");
            var fz = pt.GetField("z") ?? pt.GetField("Z");
            if (fx == null || fy == null || fz == null) return false;
            float x = (float)fx.GetValue(posObj)!;
            float y = (float)fy.GetValue(posObj)!;
            float z = (float)fz.GetValue(posObj)!;
            positions.Add(new Vec3(x, y, z));
            return true;
        }
        catch { return false; }
    }

    /// <summary>
    /// Boost score + retag spots that are within 40m of a structure. Such
    /// spots flip to Anchor role (defensive backstop) and tag "structure".
    /// </summary>
    private static void ApplyStructureProximity(List<CrestSpot> spots, List<Vec3> structures)
    {
        if (structures.Count == 0) return;
        const float ProximityM = 40f;
        foreach (var s in spots)
        {
            float bestD = float.MaxValue;
            foreach (var sp in structures)
            {
                float dx = sp.x - s.Anchor.x;
                float dy = sp.y - s.Anchor.y;
                float d  = (float)Math.Sqrt(dx * dx + dy * dy);
                if (d < bestD) bestD = d;
            }
            if (bestD <= ProximityM)
            {
                s.PickScore += 5f;
                s.TerrainTag = string.IsNullOrEmpty(s.TerrainTag) ? "structure"
                                                                  : (s.TerrainTag + ",structure");
                // Promote to Anchor role unless it's already a primary
                // assault role we don't want to overwrite.
                if (s.Role != SpotRole.Front && s.Role != SpotRole.FlankLeft && s.Role != SpotRole.FlankRight)
                {
                    s.Role = SpotRole.Anchor;
                    s.ClassPreference = ClassPref.InfantryPreferred;
                }
            }
        }
    }
}
