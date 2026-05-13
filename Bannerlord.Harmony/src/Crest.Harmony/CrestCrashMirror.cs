using System;
using System.Collections.Generic;
using System.IO;

namespace Bannerlord.Harmony;

/// <summary>
/// CREST v0.9.1 crash-report mirror.
///
/// BUTR.CrashReport writes its HTML crash dumps to
///   <c>%USERPROFILE%\Documents\Mount and Blade II Bannerlord\crashes\</c>
/// which is the standard, well-known location every Bannerlord modder asks
/// users to attach when filing bugs. The downside: it's outside the mod
/// tree, so users have to navigate to Documents to find their crash file.
///
/// CrashMirror sits on a 5-second tick (<see cref="OnTick"/>, called from
/// <see cref="SubModule.OnApplicationTick"/>), watches the Documents
/// crashes folder for new <c>crashreport*.html</c> files written after the
/// game launched, and copies any it sees into
///   <c>Modules\CREST\crashes\</c>
/// using an atomic <c>.tmp</c> + <see cref="File.Move"/> swap so a partial
/// write never leaves a half-mirrored file in the mod tree.
///
/// Net effect: the mod-tree mirror is the One Place users need to look for
/// crash artifacts, eliminating the "wait, which crashes folder?" support
/// loop that the v0.9.0 sticky-comment carved out as a known papercut.
///
/// Gated on the <c>EnableCrashMirror</c> config flag (default true). Users
/// who don't want the duplicate can flip it off in MCM or in
/// <c>crest.json</c>.
///
/// Idempotent: each mirrored filename is remembered in a HashSet so
/// repeated ticks don't re-copy. Files modified before the module's
/// start time are ignored — those are pre-existing crashes from earlier
/// sessions, not crashes from "this run".
/// </summary>
public static class CrestCrashMirror
{
    private static float _accumSec;
    private const float TickIntervalSec = 5.0f;

    private static DateTime _moduleStartTimeUtc = DateTime.UtcNow;
    private static readonly HashSet<string> _mirrored = new(StringComparer.OrdinalIgnoreCase);

    private static string? _sourceDirCached;
    private static string? _destDirCached;
    private static bool _initFailed;

    /// <summary>
    /// Module-load entry point. Captures start time and resolves source/dest
    /// directories once. Safe to call from <see cref="SubModule.OnSubModuleLoad"/>;
    /// idempotent if called multiple times.
    /// </summary>
    public static void Initialize()
    {
        try
        {
            _moduleStartTimeUtc = DateTime.UtcNow;
            _sourceDirCached = ResolveSourceDir();
            _destDirCached = ResolveDestDir();
            if (_destDirCached != null)
            {
                Directory.CreateDirectory(_destDirCached);
            }
            CrestDiag.Log("CrestCrashMirror",
                $"Initialize: source='{_sourceDirCached ?? "(unresolved)"}' dest='{_destDirCached ?? "(unresolved)"}'");
        }
        catch (Exception ex)
        {
            _initFailed = true;
            CrestDiag.LogCaught("CrestCrashMirror", "Initialize", ex);
        }
    }

    /// <summary>
    /// Per-frame tick. No-ops on every frame except every ~5 seconds, when
    /// it scans the source directory for new crashreport*.html files and
    /// mirrors any unseen ones into the mod-tree crashes folder.
    /// </summary>
    public static void OnTick(float dt)
    {
        if (_initFailed) return;
        if (!CrestConfig.IsEnabled("EnableCrashMirror", defaultValue: true)) return;

        _accumSec += dt;
        if (_accumSec < TickIntervalSec) return;
        _accumSec = 0f;

        try
        {
            if (_sourceDirCached == null) _sourceDirCached = ResolveSourceDir();
            if (_destDirCached == null) _destDirCached = ResolveDestDir();
            if (_sourceDirCached == null || _destDirCached == null) return;
            if (!Directory.Exists(_sourceDirCached)) return;

            Directory.CreateDirectory(_destDirCached);

            string[] candidates;
            try { candidates = Directory.GetFiles(_sourceDirCached, "crashreport*.html"); }
            catch { return; }

            foreach (var src in candidates)
            {
                try
                {
                    var name = Path.GetFileName(src);
                    if (_mirrored.Contains(name)) continue;

                    var mtime = File.GetLastWriteTimeUtc(src);
                    if (mtime < _moduleStartTimeUtc)
                    {
                        // Old crash from a previous session; remember so we
                        // don't re-stat it on every tick, but don't mirror.
                        _mirrored.Add(name);
                        continue;
                    }

                    var dest = Path.Combine(_destDirCached, name);
                    var tmp = dest + ".tmp";
                    File.Copy(src, tmp, overwrite: true);
                    if (File.Exists(dest))
                    {
                        try { File.Delete(dest); } catch { }
                    }
                    File.Move(tmp, dest);
                    _mirrored.Add(name);

                    CrestDiag.Log("CrestCrashMirror", $"mirrored '{name}' to Modules\\CREST\\crashes\\");
                }
                catch (Exception ex)
                {
                    CrestDiag.LogCaught("CrestCrashMirror", "OnTick.copy", ex);
                }
            }
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught("CrestCrashMirror", "OnTick", ex);
        }
    }

    private static string? ResolveSourceDir()
    {
        try
        {
            var docs = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
            if (string.IsNullOrEmpty(docs)) return null;
            return Path.Combine(docs, "Mount and Blade II Bannerlord", "crashes");
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Resolve <c>Modules\CREST\crashes\</c> by walking up from this
    /// assembly's location — same pattern as CrestConfig.ResolveConfigPath.
    /// </summary>
    private static string? ResolveDestDir()
    {
        try
        {
            var asmLoc = typeof(CrestCrashMirror).Assembly.Location;
            if (string.IsNullOrEmpty(asmLoc)) return null;
            var binDir = Path.GetDirectoryName(asmLoc);
            if (binDir == null) return null;
            var binParent = Directory.GetParent(binDir);
            if (binParent == null) return null;
            var crestRoot = binParent.Parent;
            if (crestRoot == null) return null;
            return Path.Combine(crestRoot.FullName, "crashes");
        }
        catch
        {
            return null;
        }
    }
}
