using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading.Tasks;

namespace Bannerlord.Harmony;

/// <summary>
/// Removes Windows' Mark-of-the-Web (Zone.Identifier alternate data stream)
/// from every DLL and EXE under each loaded module's folder.
///
/// Why this matters: when a player downloads CREST or a community mod as a
/// zip and extracts it, every file inside picks up an NTFS ADS named
/// "Zone.Identifier" containing the URL the file was downloaded from. The
/// .NET CLR refuses to load assemblies with that ADS unless the user manually
/// right-clicks each file and ticks "Unblock," which nobody does in practice.
/// The result is silent load failures with cryptic security exceptions.
///
/// BLSE's launcher exes do this for the bin folder when launched directly.
/// They DON'T do it when the AppDomainManager pathway kicks in (Steam-style
/// launches), and they don't cover community mod DLLs at any stage. We do.
///
/// Implementation: NTFS ADS is deleted by passing the path "file:Zone.Identifier"
/// to DeleteFileW. The Win32 call returns success when the stream existed and
/// got deleted; returns failure when the stream wasn't there. Either way the
/// file ends up with no Zone.Identifier, which is what we want, so we don't
/// branch on the return value.
///
/// Cost: enumerates files under Modules\ at startup. On a typical install
/// (~50 modules) it processes a few hundred files. Each P/Invoke is sub-ms.
/// Parallelized via Task.Parallel.ForEach so the wall-clock cost is small.
///
/// Opt-out: CrestConfig.IsEnabled("AutoUnblock") gate (default true) +
/// env var CREST_AUTO_UNBLOCK=0.
/// </summary>
internal static class CrestUnblock
{
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool DeleteFileW(string lpFileName);

    private static bool _ran;

    public static void Run()
    {
        if (_ran) return;
        _ran = true;

        if (Environment.GetEnvironmentVariable("CREST_AUTO_UNBLOCK") == "0"
            || !CrestConfig.IsEnabled("AutoUnblock"))
        {
            CrestDiag.Log(nameof(CrestUnblock), "disabled via crest.json or env var");
            return;
        }

        try
        {
            // Find Modules\ by walking up from this assembly's location.
            // Crest.Harmony.dll lives at Modules\CREST\bin\Win64_Shipping_Client\.
            // Three parents up = Modules\.
            var asmLoc = typeof(CrestUnblock).Assembly.Location;
            if (string.IsNullOrEmpty(asmLoc))
            {
                CrestDiag.Log(nameof(CrestUnblock), "could not resolve assembly location, skipping");
                return;
            }
            var binDir = Path.GetDirectoryName(asmLoc);
            var binParent = binDir != null ? Directory.GetParent(binDir) : null;
            var crestRoot = binParent?.Parent;
            var modulesRoot = crestRoot?.Parent;
            if (modulesRoot == null || !modulesRoot.Exists)
            {
                CrestDiag.Log(nameof(CrestUnblock), "could not resolve Modules\\ root, skipping");
                return;
            }

            var processed = 0;
            var locker = new object();
            var sw = System.Diagnostics.Stopwatch.StartNew();

            // Enumerate every module folder under Modules\, then every file
            // inside. We focus on .dll/.exe/.config since those are the file
            // types the CLR actually checks Zone.Identifier on.
            foreach (var moduleDir in modulesRoot.EnumerateDirectories())
            {
                var binSubdir = Path.Combine(moduleDir.FullName, "bin", "Win64_Shipping_Client");
                if (!Directory.Exists(binSubdir)) continue;

                try
                {
                    var files = Directory.EnumerateFiles(binSubdir, "*", SearchOption.TopDirectoryOnly);
                    Parallel.ForEach(files, f =>
                    {
                        if (!IsRelevantExtension(f)) return;
                        // DeleteFileW on path:Zone.Identifier; ignore return.
                        DeleteFileW(f + ":Zone.Identifier");
                        lock (locker) { processed++; }
                    });
                }
                catch (Exception ex)
                {
                    CrestDiag.LogCaught(nameof(CrestUnblock), "Run/" + moduleDir.Name, ex);
                }
            }

            // Also unblock the game's own bin\Win64_Shipping_Client\ for
            // BLSE binaries, BUTR.CrashReport.*, etc. Walk up from Modules\
            // one level to find the game root, then into bin\.
            try
            {
                var gameRoot = modulesRoot.Parent;
                if (gameRoot != null)
                {
                    var gameBin = Path.Combine(gameRoot.FullName, "bin", "Win64_Shipping_Client");
                    if (Directory.Exists(gameBin))
                    {
                        var files = Directory.EnumerateFiles(gameBin, "*", SearchOption.TopDirectoryOnly);
                        Parallel.ForEach(files, f =>
                        {
                            if (!IsRelevantExtension(f)) return;
                            DeleteFileW(f + ":Zone.Identifier");
                            lock (locker) { processed++; }
                        });
                    }
                }
            }
            catch (Exception ex)
            {
                CrestDiag.LogCaught(nameof(CrestUnblock), "Run/gameBin", ex);
            }

            sw.Stop();
            CrestDiag.Log(nameof(CrestUnblock), "processed " + processed + " files in " + sw.ElapsedMilliseconds + "ms");
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(nameof(CrestUnblock), "Run", ex);
        }
    }

    private static bool IsRelevantExtension(string path)
    {
        var ext = Path.GetExtension(path);
        if (string.IsNullOrEmpty(ext)) return false;
        ext = ext.ToLowerInvariant();
        return ext == ".dll" || ext == ".exe" || ext == ".config";
    }
}
