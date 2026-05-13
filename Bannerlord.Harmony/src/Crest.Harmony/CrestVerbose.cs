using System;
using System.IO;
using System.Text;
using System.Threading;

namespace Bannerlord.Harmony;

/// <summary>
/// Y.70 -- gated rich logging for the convergence rule path.
///
/// When the sentinel file <c>Modules\CREST\verbose.on</c> exists, every
/// <see cref="CrestFormationRules.Evaluate"/> call dumps its full input
/// vector and decision to <c>runtime-verbose.log</c> alongside the main
/// runtime.log. When the sentinel is absent the helper is a one-bool-check
/// no-op, so it is safe to leave wired in production builds.
///
/// Toggle with <c>Crest.ps1 -Mode Verbose On|Off</c> from any PS window.
/// The sentinel is checked at most once every <c>RefreshIntervalMs</c>,
/// so flipping it mid-battle takes effect within ~2 seconds without
/// requiring a SubModule reload.
/// </summary>
public static class CrestVerbose
{
    private const string Source = "CrestVerbose";
    private const int RefreshIntervalMs = 2000;
    private const string SentinelName = "verbose.on";

    private static bool _enabled;
    private static long _lastCheckTicks;
    private static string? _logPath;
    private static string? _sentinelPath;
    private static bool _pathsResolved;
    private static readonly object _gate = new();

    /// <summary>
    /// True when <c>Modules\CREST\verbose.on</c> exists. Refreshed at most
    /// once per <see cref="RefreshIntervalMs"/>, so this is cheap to check
    /// in hot per-formation loops.
    /// </summary>
    public static bool Enabled
    {
        get
        {
            var now = Environment.TickCount;
            // Tick wraparound: just refresh once on wrap.
            if (now - (int)_lastCheckTicks < RefreshIntervalMs && _lastCheckTicks != 0)
                return _enabled;
            RefreshFlag();
            return _enabled;
        }
    }

    /// <summary>
    /// Log a verbose line. Format string + args follow string.Format conventions.
    /// No-op when <see cref="Enabled"/> is false.
    /// </summary>
    public static void Log(string category, string format, params object[] args)
    {
        if (!Enabled) return;
        try
        {
            var path = ResolveLogPath();
            if (path == null) return;

            var msg = args.Length == 0 ? format : string.Format(format, args);
            var line = string.Format("[{0:HH:mm:ss.fff}] [{1}] {2}{3}",
                                      DateTime.Now, category, msg, Environment.NewLine);
            lock (_gate) { File.AppendAllText(path, line); }
        }
        catch { /* never throw out of a logging helper */ }
    }

    /// <summary>
    /// Convenience for the rule-evaluation tap. Captures the full input
    /// vector + the decision in one call so log lines stay parallel.
    /// </summary>
    public static void LogRule(
        string sideTag, int poolIdx, string label,
        bool isCav, int units, float retreatWeight,
        float anchorDist, float enemyDist, string engineMove,
        bool losToEnemy, string spotRole,
        string ruleAction, string ruleReason)
    {
        if (!Enabled) return;
        Log("rule",
            "[{0}.{1}] {2} isCav={3} units={4} retreatW={5:F2} anchorD={6:F1} enemyD={7:F1} mv={8} los={9} role={10} -> {11}: {12}",
            sideTag, poolIdx, label,
            isCav, units, retreatWeight,
            anchorDist, enemyDist, engineMove,
            losToEnemy, spotRole,
            ruleAction, ruleReason);
    }

    private static void RefreshFlag()
    {
        try
        {
            var sentinel = ResolveSentinelPath();
            if (sentinel == null) { _enabled = false; }
            else { _enabled = File.Exists(sentinel); }
        }
        catch { _enabled = false; }
        Interlocked.Exchange(ref _lastCheckTicks, Environment.TickCount);
    }

    private static string? ResolveLogPath()
    {
        ResolvePathsOnce();
        return _logPath;
    }

    private static string? ResolveSentinelPath()
    {
        ResolvePathsOnce();
        return _sentinelPath;
    }

    private static void ResolvePathsOnce()
    {
        if (_pathsResolved) return;
        _pathsResolved = true;
        try
        {
            var asmLoc = typeof(CrestVerbose).Assembly.Location;
            if (string.IsNullOrEmpty(asmLoc)) return;
            var binDir = Path.GetDirectoryName(asmLoc);
            if (binDir == null) return;
            var binParent = Directory.GetParent(binDir);
            if (binParent == null) return;
            var crestRoot = binParent.Parent;
            if (crestRoot == null) return;
            _logPath      = Path.Combine(crestRoot.FullName, "runtime-verbose.log");
            _sentinelPath = Path.Combine(crestRoot.FullName, SentinelName);
        }
        catch { /* leave both null -> Enabled stays false */ }
    }

    /// <summary>
    /// Diagnostic -- emits the resolved paths to runtime.log so the agent
    /// can verify it landed in the right CREST module folder.
    /// </summary>
    public static void DumpPathsForDiag()
    {
        ResolvePathsOnce();
        CrestDiag.Log(Source, "verbose log:      " + (_logPath ?? "<unresolved>"));
        CrestDiag.Log(Source, "verbose sentinel: " + (_sentinelPath ?? "<unresolved>"));
        CrestDiag.Log(Source, "verbose enabled:  " + Enabled);
    }
}
