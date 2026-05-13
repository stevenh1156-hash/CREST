using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading;

namespace Bannerlord.Harmony;

/// <summary>
/// Centralized append-only diagnostic logger for CREST. Used by Crest.* modules
/// to record patch-binding outcomes, AccessTools lookups that returned null,
/// catch blocks that swallowed exceptions, and other "would-be-silent failures."
///
/// Anchored on this assembly's location so it always lands at
///   Modules\CREST\runtime.log
/// for installed users (where they can find it without a dev path), and at
/// the dev tree's runtime.log for in-house builds. Falls back to a no-op when
/// the path can't be resolved or the write fails -- never throws.
///
/// Why a separate file rather than ButterLib's Serilog logger: this needs to
/// work BEFORE ButterLib finishes initializing (Crest.Harmony.SubModule loads
/// first), and it needs to survive ButterLib's logger being disabled via
/// CrestConfig. Append-only file write is the lowest-common-denominator that
/// satisfies both constraints.
///
/// Z.6 perf-A: writes are now buffered. Each Log() enqueues a line in memory
/// and a background timer (1Hz) flushes the buffer to disk in one
/// File.AppendAllText call. Saves ~30-60 syscalls per battle when convergence
/// is firing. Also produces cleaner crash logs -- the previous per-call
/// AppendAllText pattern would leave the file with trailing nulls when the
/// process died mid-write; with the timer flush model the buffer is either
/// fully written or not, no partial-record states. Flush also fires on
/// AppDomain unload as a final sweep so the last few lines aren't lost on
/// clean shutdown.
/// </summary>
/// <remarks>
/// <b>Public API for consumer mods (Phase Y.9).</b> Mods that depend on CREST
/// can call <see cref="Log"/>, <see cref="LogCaught"/>, and <see cref="LogTypeNotFound"/>
/// to write to the same shared <c>Modules\CREST\runtime.log</c> file. This is
/// the recommended way for CREST-dependent mods to record diagnostics: it
/// works before ButterLib initializes, the path is well-known to users for
/// support purposes, and Crest-Doctor's diagnostic tooling pulls from this
/// same file.
/// </remarks>
public static class CrestDiag
{
    // Z.6 perf-A: buffered writer state.
    private static readonly object _lock = new();
    private static readonly Queue<string> _buffer = new();
    private static string? _resolvedPath;
    private static bool _resolveAttempted;
    private static Timer? _flushTimer;
    private static int _flushTimerStarted;          // 0 = not started, 1 = started (Interlocked)

    // Tunables. The 1-second flush gives a good balance between latency
    // (so users tailing the log see updates) and syscall count (one IO
    // per second instead of one per Log call). MaxBufferLines is a safety
    // ceiling -- if logging spikes faster than the flush, we still cap memory.
    private const int FlushIntervalMs = 1000;
    private const int MaxBufferLines  = 4096;

    /// <summary>
    /// Append a diagnostic line. Format: "[YYYY-MM-DD HH:mm:ss.fff] [Source] message".
    /// Source is typically the calling class name (e.g., "CrestMessageStyle").
    /// </summary>
    public static void Log(string source, string message)
    {
        if (ResolveLogPath() == null) return;
        try
        {
            var ts = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff");
            var line = "[" + ts + "] [" + source + "] " + message + Environment.NewLine;
            lock (_lock)
            {
                _buffer.Enqueue(line);
                // Backpressure: if buffer balloons (something's logging in a tight
                // loop) flush synchronously to release memory. Should be rare;
                // most paths produce <100 lines/sec.
                if (_buffer.Count > MaxBufferLines) FlushLocked();
            }
            // Lazy timer init: only spin up the flush thread once we've
            // actually got something to log. Avoids creating a Timer for
            // installs where CREST loads but never logs.
            if (Interlocked.CompareExchange(ref _flushTimerStarted, 1, 0) == 0)
            {
                _flushTimer = new Timer(FlushCallback, null, FlushIntervalMs, FlushIntervalMs);
                AppDomain.CurrentDomain.ProcessExit += (_, _2) => Flush();
                AppDomain.CurrentDomain.DomainUnload += (_, _2) => Flush();
            }
        }
        catch
        {
            // never throw from a diagnostic logger.
        }
    }

    /// <summary>
    /// Compact form for "tried to look up TaleWorlds.X.Y but it returned null."
    /// </summary>
    public static void LogTypeNotFound(string source, string typeName)
        => Log(source, "AccessTools2.TypeByName returned null for: " + typeName);

    /// <summary>
    /// Compact form for "exception was caught and swallowed."
    /// </summary>
    public static void LogCaught(string source, string context, Exception ex)
        => Log(source, "caught in " + context + ": " + ex.GetType().Name + " " + ex.Message);

    /// <summary>
    /// Force-flush the buffer to disk. Called from the 1Hz timer, on AppDomain
    /// unload, and from inside Log() when the buffer hits its max ceiling.
    /// Public so consumers can flush before reading the log themselves
    /// (e.g., Crest-Doctor when running a live diagnostic).
    /// </summary>
    public static void Flush()
    {
        lock (_lock) { FlushLocked(); }
    }

    private static void FlushCallback(object? state)
    {
        try { Flush(); } catch { /* never throw from a timer callback */ }
    }

    /// <summary>Flush implementation; caller must hold _lock.</summary>
    private static void FlushLocked()
    {
        if (_buffer.Count == 0) return;
        var path = _resolvedPath;
        if (path == null) return;

        // Pull everything from the queue into one StringBuilder so the
        // File.AppendAllText is a single syscall. Even if the buffer has
        // hundreds of lines we still do one open/write/close cycle.
        var sb = new StringBuilder(Math.Min(_buffer.Count * 80, 65536));
        while (_buffer.Count > 0) sb.Append(_buffer.Dequeue());

        try { File.AppendAllText(path, sb.ToString()); }
        catch { /* never throw -- file might be locked by tail readers */ }
    }

    private static string? ResolveLogPath()
    {
        if (_resolveAttempted) return _resolvedPath;
        _resolveAttempted = true;
        try
        {
            var asmLoc = typeof(CrestDiag).Assembly.Location;
            if (string.IsNullOrEmpty(asmLoc)) return null;
            // Crest.Harmony.dll lives at Modules\CREST\bin\Win64_Shipping_Client\.
            // Two parents up = Modules\CREST. runtime.log lives at the module root.
            var binDir = Path.GetDirectoryName(asmLoc);
            if (binDir == null) return null;
            var binParent = Directory.GetParent(binDir);
            if (binParent == null) return null;
            var crestRoot = binParent.Parent;
            if (crestRoot == null) return null;
            _resolvedPath = Path.Combine(crestRoot.FullName, "runtime.log");
            return _resolvedPath;
        }
        catch
        {
            return null;
        }
    }
}
