using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

using Newtonsoft.Json;

using Bannerlord.Harmony;

namespace Crest.Harmony.Sim;

/// <summary>
/// Tier-2 scenario runner for CREST formation rules.
///
/// Loads a JSON scenario describing a synthetic battle (formations + a
/// timeline of state snapshots), feeds each tick through
/// <see cref="CrestFormationRules.Evaluate"/>, and writes Y.42-format
/// log lines + Y.54/Y.56 override events to a runtime.log-format file.
///
/// Crest-Diag.ps1 can read that output the same way it reads real
/// battle logs. Catches regressions in rule thresholds and override
/// stickiness without requiring a real Bannerlord battle.
///
/// Usage:
///   dotnet run -- scenarios/wandering-archers.json [output.log]
///   dotnet run -- scenarios/                       (run all scenarios)
/// </summary>
public static class Program
{
    private const string Source = "CrestBattleConvergenceLogic";

    public static int Main(string[] args)
    {
        if (args.Length == 0)
        {
            Console.Error.WriteLine("usage: Crest.Harmony.Sim <scenario.json | scenario-dir> [output.log]");
            Console.Error.WriteLine("       Crest.Harmony.Sim --replay <recorded.jsonl>");
            return 2;
        }

        // Y.70 Phase 7: replay mode. Reads a JSONL file produced by
        // CrestRecorder during a real battle and reruns each tick through
        // CrestFormationRules.Evaluate, comparing the live decision against
        // the one captured at battle time. Surfaces drift when rule code
        // changes between record and replay.
        if (args[0] == "--replay")
        {
            if (args.Length < 2)
            {
                Console.Error.WriteLine("usage: Crest.Harmony.Sim --replay <recorded.jsonl>");
                return 2;
            }
            return RunReplay(args[1]);
        }

        var input = args[0];
        var output = args.Length >= 2 ? args[1] : "sim-runtime.log";

        var scenarioPaths = new List<string>();
        if (Directory.Exists(input))
        {
            scenarioPaths.AddRange(Directory.GetFiles(input, "*.json").OrderBy(p => p));
        }
        else if (File.Exists(input))
        {
            scenarioPaths.Add(input);
        }
        else
        {
            Console.Error.WriteLine($"not found: {input}");
            return 2;
        }

        // Truncate output -- one fresh log per sim invocation.
        File.WriteAllText(output, string.Empty);

        var totalChecks = 0;
        var totalOverrides = 0;
        var failures = new List<string>();

        foreach (var path in scenarioPaths)
        {
            Console.WriteLine($"== {Path.GetFileNameWithoutExtension(path)} ==");
            var scenario = LoadScenario(path);
            var (checks, overrides, scenarioFailures) = RunScenario(scenario, output);
            totalChecks += checks;
            totalOverrides += overrides;
            failures.AddRange(scenarioFailures);
            Console.WriteLine($"   ticks={checks} overrides={overrides} failures={scenarioFailures.Count}");
        }

        Console.WriteLine();
        Console.WriteLine($"Total: ticks={totalChecks} overrides={totalOverrides} failures={failures.Count}");
        Console.WriteLine($"Log:   {Path.GetFullPath(output)}");

        if (failures.Count > 0)
        {
            Console.Error.WriteLine();
            Console.Error.WriteLine("FAILED ASSERTIONS:");
            foreach (var f in failures) Console.Error.WriteLine("  " + f);
            return 1;
        }
        return 0;
    }

    private static Scenario LoadScenario(string path)
    {
        var json = File.ReadAllText(path);
        // Newtonsoft is case-insensitive by default and accepts trailing
        // commas + comments out of the box -- no extra config needed.
        var s = JsonConvert.DeserializeObject<Scenario>(json)
            ?? throw new InvalidOperationException($"failed to parse {path}");
        s.SourcePath = path;
        return s;
    }

    /// <summary>
    /// Y.70 Phase 7: replay mode. Reads a JSONL recording from CrestRecorder,
    /// re-evaluates each tick against the current rule code, and reports
    /// matches / divergences. Useful when a rule changes between battles to
    /// see how many decisions would have been different.
    /// </summary>
    private static int RunReplay(string jsonlPath)
    {
        if (!File.Exists(jsonlPath))
        {
            Console.Error.WriteLine($"replay file not found: {jsonlPath}");
            return 2;
        }

        Console.WriteLine($"== replay {Path.GetFileName(jsonlPath)} ==");
        var lines = File.ReadAllLines(jsonlPath);

        int total = 0, matches = 0;
        var divergences = new List<string>();
        var actionHistogram = new Dictionary<string, int>();
        var divergenceByRule = new Dictionary<string, int>();
        string? schemaVersion = null;

        foreach (var raw in lines)
        {
            var line = raw.Trim();
            if (string.IsNullOrEmpty(line)) continue;

            // Header line: {"schema":"crest-recorder/v1","startedAt":"..."}
            if (line.Contains("\"schema\""))
            {
                try
                {
                    var hdr = JsonConvert.DeserializeObject<Dictionary<string, object>>(line);
                    if (hdr != null && hdr.TryGetValue("schema", out var s)) schemaVersion = s?.ToString();
                } catch { }
                continue;
            }

            ReplayTick? tick;
            try
            {
                tick = JsonConvert.DeserializeObject<ReplayTick>(line);
            }
            catch (Exception ex)
            {
                divergences.Add($"  parse error: {ex.Message}  raw={line}");
                continue;
            }
            if (tick == null) continue;

            total++;
            // Re-evaluate the same input vector with TODAY's rule code.
            var live = CrestFormationRules.Evaluate(
                isCav:        tick.IsCav,
                units:        tick.Units,
                retreatWeight: tick.RetreatW,
                anchorDist:   tick.AnchorD,
                enemyDist:    tick.EnemyD,
                engineMove:   tick.EngineMove ?? string.Empty,
                losToEnemy:   tick.LosToEnemy,
                spotRole:     tick.SpotRole ?? string.Empty);

            var liveAction = live.Action.ToString();
            var key = liveAction;
            actionHistogram[key] = actionHistogram.TryGetValue(key, out var c0) ? c0 + 1 : 1;

            if (string.Equals(liveAction, tick.RuleAction, StringComparison.Ordinal))
            {
                matches++;
            }
            else
            {
                var ruleKey = $"{tick.RuleAction} -> {liveAction}";
                divergenceByRule[ruleKey] = divergenceByRule.TryGetValue(ruleKey, out var c1) ? c1 + 1 : 1;
                if (divergences.Count < 25) // cap inline detail to keep output readable
                {
                    divergences.Add(
                        $"  t={tick.At,6:F1} [{tick.Side}.{tick.Pool}] {tick.Label}  was={tick.RuleAction}  now={liveAction}  " +
                        $"(units={tick.Units} anchorD={tick.AnchorD:F1} enemyD={tick.EnemyD:F1} mv={tick.EngineMove} los={tick.LosToEnemy} role={tick.SpotRole})");
                }
            }
        }

        Console.WriteLine($"  schema:    {schemaVersion ?? "<none>"}");
        Console.WriteLine($"  total:     {total} ticks");
        Console.WriteLine($"  matches:   {matches} ({(total == 0 ? 0 : 100.0 * matches / total):F1}%)");
        Console.WriteLine($"  drift:     {total - matches}");
        Console.WriteLine();

        Console.WriteLine("  current rule action histogram:");
        foreach (var kv in actionHistogram.OrderByDescending(k => k.Value))
        {
            Console.WriteLine($"    {kv.Key,-16} {kv.Value}");
        }

        if (divergenceByRule.Count > 0)
        {
            Console.WriteLine();
            Console.WriteLine("  divergence by transition (was -> now):");
            foreach (var kv in divergenceByRule.OrderByDescending(k => k.Value))
            {
                Console.WriteLine($"    {kv.Key,-30} {kv.Value}");
            }
        }

        if (divergences.Count > 0)
        {
            Console.WriteLine();
            Console.WriteLine($"  first {divergences.Count} divergences:");
            foreach (var d in divergences) Console.WriteLine(d);
        }

        // Replay never "fails" the build — drift is a report, not a regression.
        // Crest-Postmortem can compare drift counts across versions to spot
        // unintended rule-behavior changes.
        return 0;
    }

    /// <summary>JSONL row produced by CrestRecorder.</summary>
    private sealed class ReplayTick
    {
        public float  At         { get; set; }
        public string Side       { get; set; } = string.Empty;
        public int    Pool       { get; set; }
        public string Label      { get; set; } = string.Empty;
        public bool   IsCav      { get; set; }
        public int    Units      { get; set; }
        public float  RetreatW   { get; set; }
        public float  AnchorD    { get; set; }
        public float  EnemyD     { get; set; }
        public string EngineMove { get; set; } = string.Empty;
        public bool   LosToEnemy { get; set; }
        public string SpotRole   { get; set; } = string.Empty;
        public string RuleAction { get; set; } = string.Empty;
        public string RuleReason { get; set; } = string.Empty;
    }

    private static (int checks, int overrides, List<string> failures) RunScenario(
        Scenario scenario, string outputLogPath)
    {
        var checks = 0;
        var overrides = 0;
        var failures = new List<string>();

        // Y.56-equivalent: model the sticky override dictionary in the sim.
        // Key = formation id ("ally.0.arch"), value = the active override action.
        // When a rule fires we write to the dict; when no rule matches we
        // remove it (and emit a Y.56 clear line).
        var stickyOverrides = new Dictionary<string, Y54Action>();

        var startTime = new DateTime(2026, 5, 9, 12, 0, 0);

        foreach (var tick in scenario.Ticks)
        {
            var t = startTime.AddSeconds(tick.At);
            var ts = t.ToString("yyyy-MM-dd HH:mm:ss.fff");

            foreach (var f in tick.Formations)
            {
                checks++;

                // Y.42 snapshot line, same format the production diag emits.
                Append(outputLogPath,
                    $"[{ts}] [{Source}] Y.42 [{f.PoolId}] {f.Class}: " +
                    $"units={f.Units} pos=({f.Pos[0]:F1},{f.Pos[1]:F1}) " +
                    $"anchorD={f.AnchorD:F1} enemyD={f.EnemyD:F1} " +
                    $"engineMove={f.EngineMove} engineArr={f.EngineArr} " +
                    $"wantMove={f.WantMove} wantArr={f.WantArr} beh={f.Beh} " +
                    $"weights=Charge:{f.ChargeWeight:F2}x10000.00,Retreat:{f.RetreatWeight:F2}x0.00 " +
                    $"captain={f.Captain ?? "null"}");

                // Run the rule.
                var decision = CrestFormationRules.Evaluate(
                    isCav: f.Class == "cav",
                    units: f.Units,
                    retreatWeight: f.RetreatWeight,
                    anchorDist: f.AnchorD,
                    enemyDist: f.EnemyD,
                    engineMove: f.EngineMove,
                    losToEnemy: f.LosToEnemy,
                    spotRole: f.SpotRole);

                var fid = $"{f.PoolId}.{f.Class}";
                if (decision.Action != Y54Action.None)
                {
                    overrides++;
                    stickyOverrides[fid] = decision.Action;
                    Append(outputLogPath,
                        $"[{ts}] [{Source}] Y.54 override: [{f.PoolId}] {f.Class} " +
                        $"{CrestFormationRules.ActionShortName(decision.Action)}: {decision.Reason}");
                }
                else if (stickyOverrides.Remove(fid))
                {
                    Append(outputLogPath,
                        $"[{ts}] [{Source}] Y.56 clear: [{f.PoolId}] {f.Class} override released " +
                        $"(anchorD={f.AnchorD:F1} enemyD={f.EnemyD:F1} units={f.Units} engineMove={f.EngineMove})");
                }

                // Optional assertion: scenario can declare expected action per tick.
                if (!string.IsNullOrEmpty(f.ExpectAction))
                {
                    var expected = ParseExpect(f.ExpectAction);
                    if (decision.Action != expected)
                    {
                        failures.Add(
                            $"{Path.GetFileName(scenario.SourcePath)}:t={tick.At} {fid}: " +
                            $"expected {expected} got {decision.Action} (reason: {decision.Reason})");
                    }
                }
            }
        }

        return (checks, overrides, failures);
    }

    private static void Append(string path, string line)
    {
        File.AppendAllText(path, line + Environment.NewLine);
    }

    private static Y54Action ParseExpect(string s) => s.ToLowerInvariant() switch
    {
        "none"           or "" => Y54Action.None,
        "cavunstuck"     or "cav-unstuck"    => Y54Action.CavUnstuck,
        "brokenretreat"  or "broken-retreat" => Y54Action.BrokenRetreat,
        "wanderclamp"    or "wander-clamp"   => Y54Action.WanderClamp,
        "noloss"         or "no-los"         or "holdnolos"   => Y54Action.HoldNoLOS,
        "ambush"         or "ambush-hold"    or "ambushhold"  => Y54Action.AmbushHold,
        _ => throw new ArgumentException($"unknown expect-action: {s}"),
    };

    // -- scenario model --------------------------------------------------

    public class Scenario
    {
        public string Name { get; set; } = "";
        public string Description { get; set; } = "";
        public List<Tick> Ticks { get; set; } = new();

        // populated at load time
        public string SourcePath { get; set; } = "";
    }

    public class Tick
    {
        /// <summary>seconds since scenario start</summary>
        public float At { get; set; }
        public List<FormationState> Formations { get; set; } = new();
    }

    public class FormationState
    {
        /// <summary>e.g. "ally.0", "enemy.1"</summary>
        public string PoolId { get; set; } = "ally.0";
        /// <summary>"inf", "arch", "cav"</summary>
        public string Class { get; set; } = "inf";

        public int Units { get; set; }
        public float[] Pos { get; set; } = new float[] { 0, 0 };
        public float AnchorD { get; set; }
        public float EnemyD { get; set; }

        // engine-side state
        public string EngineMove { get; set; } = "Advance";
        public string EngineArr { get; set; } = "Line";
        public string WantMove { get; set; } = "Advance";
        public string WantArr { get; set; } = "Line";
        public string Beh { get; set; } = "Advance";
        public string? Captain { get; set; } = null;

        // weights of interest
        public float ChargeWeight { get; set; } = 0.10f;
        public float RetreatWeight { get; set; } = 0.30f;

        // Y.66: line-of-sight to enemy (default true = LOS clear, no override).
        public bool LosToEnemy { get; set; } = true;
        // Y.67: spot role (e.g. "Ambush" triggers AmbushHold rule).
        public string SpotRole { get; set; } = "";

        /// <summary>Optional: scenario assertion -- expected Y54Action this tick.</summary>
        public string ExpectAction { get; set; } = "";
    }
}
