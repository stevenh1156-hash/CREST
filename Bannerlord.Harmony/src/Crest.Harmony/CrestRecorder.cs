using System;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;

namespace Bannerlord.Harmony;

/// <summary>
/// Y.70 -- battle-replay capture. Records every per-formation rule-evaluation
/// tick into a JSONL file so the offline sim harness can replay the same
/// inputs against a future rule build and report drift.
///
/// Gated by sentinel <c>Modules\CREST\record.on</c>. When absent the API
/// is a one-bool-check no-op. One JSONL file per recording session at
/// <c>Modules\CREST\record-&lt;stamp&gt;.jsonl</c>; the stamp is the moment
/// recording was first enabled in the SubModule.
///
/// The schema is intentionally flat and stable -- see <see cref="WriteHeader"/>
/// for the column order. Keep it append-only.
///
/// Toggle with <c>Crest.ps1 -Mode Record On|Off</c> (Phase 7).
/// </summary>
public static class CrestRecorder
{
    private const string Source = "CrestRecorder";
    private const int RefreshIntervalMs = 2000;
    private const string SentinelName = "record.on";

    private static bool _enabled;
    private static long _lastCheckTicks;
    private static string? _crestRoot;
    private static string? _sentinelPath;
    private static string? _activeJsonlPath;
    private static bool _pathsResolved;
    private static readonly object _gate = new();

    public static bool Enabled
    {
        get
        {
            var now = Environment.TickCount;
            if (now - (int)_lastCheckTicks < RefreshIntervalMs && _lastCheckTicks != 0)
                return _enabled;
            RefreshFlag();
            return _enabled;
        }
    }

    /// <summary>
    /// Append one tick to the current recording session. No-op when
    /// <see cref="Enabled"/> is false.
    /// </summary>
    public static void RecordTick(
        float at,            // mission elapsed seconds
        string sideTag, int poolIdx, string label,
        bool isCav, int units, float retreatWeight,
        float anchorDist, float enemyDist, string engineMove,
        bool losToEnemy, string spotRole,
        string ruleAction, string ruleReason)
    {
        if (!Enabled) return;
        try
        {
            var path = ResolveJsonlPath();
            if (path == null) return;

            // Hand-built JSON. Avoids pulling Newtonsoft into Crest.Harmony,
            // and keeps the schema strictly under our control.
            var ci = CultureInfo.InvariantCulture;
            var sb = new StringBuilder(256);
            sb.Append('{');
            sb.Append("\"at\":").Append(at.ToString("F2", ci)).Append(',');
            sb.Append("\"side\":\"").Append(JsonEscape(sideTag)).Append("\",");
            sb.Append("\"pool\":").Append(poolIdx.ToString(ci)).Append(',');
            sb.Append("\"label\":\"").Append(JsonEscape(label)).Append("\",");
            sb.Append("\"isCav\":").Append(isCav ? "true" : "false").Append(',');
            sb.Append("\"units\":").Append(units.ToString(ci)).Append(',');
            sb.Append("\"retreatW\":").Append(retreatWeight.ToString("F3", ci)).Append(',');
            sb.Append("\"anchorD\":").Append(anchorDist.ToString("F2", ci)).Append(',');
            sb.Append("\"enemyD\":").Append(enemyDist.ToString("F2", ci)).Append(',');
            sb.Append("\"engineMove\":\"").Append(JsonEscape(engineMove)).Append("\",");
            sb.Append("\"losToEnemy\":").Append(losToEnemy ? "true" : "false").Append(',');
            sb.Append("\"spotRole\":\"").Append(JsonEscape(spotRole)).Append("\",");
            sb.Append("\"ruleAction\":\"").Append(JsonEscape(ruleAction)).Append("\",");
            sb.Append("\"ruleReason\":\"").Append(JsonEscape(ruleReason)).Append("\"");
            sb.Append('}');
            sb.Append(Environment.NewLine);

            lock (_gate) { File.AppendAllText(path, sb.ToString()); }
        }
        catch { /* never throw out of a recorder */ }
    }

    private static string JsonEscape(string s)
    {
        if (string.IsNullOrEmpty(s)) return string.Empty;
        // Keep it minimal -- these fields are short identifiers, not free text.
        return s.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "").Replace("\n", " ");
    }

    private static void RefreshFlag()
    {
        try
        {
            ResolvePathsOnce();
            if (_sentinelPath == null) { _enabled = false; }
            else
            {
                var was = _enabled;
                _enabled = File.Exists(_sentinelPath);
                if (_enabled && !was)
                {
                    // Recording just turned on -- open a fresh JSONL file
                    // stamped with the current time so we never overwrite
                    // a prior run.
                    _activeJsonlPath = null;     // force reopen via ResolveJsonlPath
                    _ = ResolveJsonlPath();      // also writes the header line
                    CrestDiag.Log(Source, "recording ENABLED -> " + (_activeJsonlPath ?? "<unresolved>"));
                }
                else if (!_enabled && was)
                {
                    CrestDiag.Log(Source, "recording DISABLED");
                    _activeJsonlPath = null;
                }
            }
        }
        catch { _enabled = false; }
        Interlocked.Exchange(ref _lastCheckTicks, Environment.TickCount);
    }

    private static string? ResolveJsonlPath()
    {
        ResolvePathsOnce();
        if (_crestRoot == null) return null;
        if (_activeJsonlPath != null) return _activeJsonlPath;
        var stamp = DateTime.Now.ToString("yyyyMMdd-HHmmss");
        _activeJsonlPath = Path.Combine(_crestRoot, "record-" + stamp + ".jsonl");
        try
        {
            // Header line -- a JSON object with a single 'schema' field marks
            // the stream as ours and is easy to skip in the replay reader.
            var header = "{\"schema\":\"crest-recorder/v1\",\"startedAt\":\"" +
                         DateTime.Now.ToString("o") + "\"}" + Environment.NewLine;
            File.AppendAllText(_activeJsonlPath, header);
        }
        catch { /* file might be locked; recorder will just fail-quiet */ }
        return _activeJsonlPath;
    }

    private static void ResolvePathsOnce()
    {
        if (_pathsResolved) return;
        _pathsResolved = true;
        try
        {
            var asmLoc = typeof(CrestRecorder).Assembly.Location;
            if (string.IsNullOrEmpty(asmLoc)) return;
            var binDir = Path.GetDirectoryName(asmLoc);
            if (binDir == null) return;
            var binParent = Directory.GetParent(binDir);
            if (binParent == null) return;
            var crestRoot = binParent.Parent;
            if (crestRoot == null) return;
            _crestRoot    = crestRoot.FullName;
            _sentinelPath = Path.Combine(_crestRoot, SentinelName);
        }
        catch { /* leave null */ }
    }

    public static void DumpPathsForDiag()
    {
        ResolvePathsOnce();
        CrestDiag.Log(Source, "record root:     " + (_crestRoot ?? "<unresolved>"));
        CrestDiag.Log(Source, "record sentinel: " + (_sentinelPath ?? "<unresolved>"));
        CrestDiag.Log(Source, "record active:   " + (_activeJsonlPath ?? "<not started>"));
        CrestDiag.Log(Source, "record enabled:  " + Enabled);
    }
}
