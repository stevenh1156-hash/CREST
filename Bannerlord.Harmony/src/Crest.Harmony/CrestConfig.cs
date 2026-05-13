using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;

namespace Bannerlord.Harmony;

/// <summary>
/// CREST runtime configuration loader.
///
/// Reads <c>Modules/CREST/crest.json</c> at first access and caches the parsed flags.
/// (Filename intentionally distinct from BetterExceptionWindow's <c>config.json</c>
/// which is also dropped into <c>Modules/CREST/</c> when BEW assets are bundled.)
/// The file is shared by all Crest.* SubModules via a small file-link copy in each fork's
/// csproj (so Crest.ButterLib, Crest.UIExtenderEx, Crest.MCM can each read the same flags
/// without taking a hard project dependency on Bannerlord.Harmony.dll).
///
/// File format:
/// <code>
/// {
///   "enabled": {
///     "Harmony": true,
///     "ButterLib": true,
///     "ButterLibImplementationLoader": true,
///     "UIExtenderEx": true,
///     "MCM": true,
///     "MCMBasicImplementation": true,
///     "SkipIntroVideo": true
///   }
/// }
/// </code>
///
/// If the file doesn't exist on first access, a default with everything enabled is
/// written so users have something to edit. Smart first-launch detection (auto-detecting
/// which sub-modules are needed by the user's mod list) is deferred to Stage 2 of Phase L.
///
/// Manual JSON editing today; in-game MCM checkboxes will layer on top of this once
/// Phase D.4 (MCM UI deep diagnosis) is resolved.
/// </summary>
public static class CrestConfig
{
    private static Dictionary<string, bool>? _enabled;
    private static Dictionary<string, string>? _strings;
    private static long _loadedMtimeTicks;     // ticks of crest.json when last loaded; 0 = unloaded
    private static readonly object _lock = new();

    /// <summary>
    /// Returns whether the named runtime flag is enabled in <c>Modules/CREST/crest.json</c>.
    /// </summary>
    /// <param name="key">
    /// Flag name (case-insensitive -- the underlying dictionary uses
    /// <see cref="StringComparer.OrdinalIgnoreCase"/>). Examples:
    /// <c>"ButterLib"</c>, <c>"MCMUI"</c>, <c>"SkipIntroVideo"</c>,
    /// <c>"MainMenuMonotone"</c>, <c>"SuppressMainMenuMessages"</c>,
    /// <c>"AutoUnblock"</c>.
    /// </param>
    /// <param name="defaultValue">
    /// Value returned when the key is absent from the parsed config. Default is
    /// <c>true</c> -- fail-open. A user with a malformed or missing
    /// <c>crest.json</c> gets every CREST feature enabled rather than every
    /// feature disabled. This is intentional: the alternative would silently
    /// brick the install. Pass <c>false</c> only for opt-in features that
    /// should stay off until the user explicitly enables them.
    /// </param>
    /// <returns><c>true</c> if the flag is set true (or absent and <paramref name="defaultValue"/> is true); otherwise <c>false</c>.</returns>
    public static bool IsEnabled(string key, bool defaultValue = true)
    {
        EnsureLoaded();
        return _enabled!.TryGetValue(key, out var v) ? v : defaultValue;
    }

    /// <summary>
    /// String-valued config lookup (Phase W.3 addition). Returns the raw
    /// string from <c>crest.json</c> if a quoted-string value is present
    /// for the key, or <paramref name="defaultValue"/> otherwise. Used by
    /// <see cref="CrestCampaignLogFilter"/> for the multi-level scope
    /// dropdown ("None" / "All" / "Party only" / "Clan only" / "Kingdom only").
    /// Falls back to bool dict if the key happens to be bool-valued
    /// ("true"/"false").
    /// </summary>
    public static string GetString(string key, string defaultValue = "")
    {
        EnsureLoaded();
        if (_strings != null && _strings.TryGetValue(key, out var s)) return s;
        if (_numbers != null && _numbers.TryGetValue(key, out var n)) return n.ToString(System.Globalization.CultureInfo.InvariantCulture);
        if (_enabled != null && _enabled.TryGetValue(key, out var b)) return b ? "true" : "false";
        return defaultValue;
    }

    /// <summary>
    /// Numeric (float) lookup. Returns the parsed JSON number for the key,
    /// or <paramref name="defaultValue"/> if the key is missing or
    /// non-numeric. Used by mod absorptions that store sliders / hotkey
    /// codes / multipliers in <c>crest.json</c>.
    /// </summary>
    public static float GetFloat(string key, float defaultValue = 0f)
    {
        EnsureLoaded();
        if (_numbers != null && _numbers.TryGetValue(key, out var n)) return (float) n;
        if (_strings != null && _strings.TryGetValue(key, out var s) &&
            float.TryParse(s, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var parsed))
            return parsed;
        return defaultValue;
    }

    public static int GetInt(string key, int defaultValue = 0)
    {
        EnsureLoaded();
        if (_numbers != null && _numbers.TryGetValue(key, out var n)) return (int) n;
        if (_strings != null && _strings.TryGetValue(key, out var s) &&
            int.TryParse(s, System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out var parsed))
            return parsed;
        return defaultValue;
    }

    private static Dictionary<string, double>? _numbers;

    private static long _lastMtimeCheckTicks;
    private static readonly long MtimeCheckIntervalTicks = TimeSpan.TicksPerMillisecond * 500;

    private static void EnsureLoaded()
    {
        // Phase W.23: cache invalidation by file mtime. CrestSettings (in
        // the MCM UI assembly) writes to crest.json on every dropdown /
        // checkbox change so MCM-side state stays in sync with the patch's
        // runtime view. Without invalidation, the patch read this dict once
        // at first call and saw stale values for the rest of the session.
        //
        // Phase W.25: throttle the file metadata stat to once per ~500ms.
        // Bannerlord fires DisplayMessage / NewLogEntryAdded in tight bursts
        // during heavy world-map ticks, and File.GetLastWriteTimeUtc isn't
        // free across thousands of calls. The user's MCM toggle latency is
        // imperceptibly different (500ms vs 0ms) but the per-call savings
        // matter at scope=Kingdom only where the path is exercised hardest.
        var nowTicks = DateTime.UtcNow.Ticks;
        if (_enabled != null && nowTicks - _lastMtimeCheckTicks < MtimeCheckIntervalTicks) return;

        var configPath = ResolveConfigPath();
        long currentMtime = 0;
        try { if (configPath != null && File.Exists(configPath)) currentMtime = File.GetLastWriteTimeUtc(configPath).Ticks; }
        catch { /* ignore */ }
        _lastMtimeCheckTicks = nowTicks;

        if (_enabled != null && currentMtime == _loadedMtimeTicks) return;

        lock (_lock)
        {
            // Re-check inside lock; another thread may have just reloaded.
            if (_enabled != null && currentMtime == _loadedMtimeTicks) return;

            var d = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
            // Reset the strings + numbers dicts too so deleted keys reflect.
            _strings = null;
            _numbers = null;
            try
            {
                if (configPath != null)
                {
                    if (!File.Exists(configPath))
                    {
                        try { WriteDefault(configPath); } catch { /* best-effort */ }
                        try { currentMtime = File.GetLastWriteTimeUtc(configPath).Ticks; } catch { }
                    }
                    if (File.Exists(configPath))
                    {
                        ParseSimpleJson(File.ReadAllText(configPath), d);
                    }
                }
            }
            catch
            {
                // never fail to load -- leave dict empty so IsEnabled returns defaults
            }
            _enabled = d;
            _loadedMtimeTicks = currentMtime;
        }
    }

    /// <summary>
    /// Walk up from this assembly's location to find the Modules\CREST\config.json path.
    /// Layout: Modules\CREST\bin\Win64_Shipping_Client\Bannerlord.Harmony.dll → ../../config.json
    /// </summary>
    private static string? ResolveConfigPath()
    {
        try
        {
            var asmLoc = typeof(CrestConfig).Assembly.Location;
            if (string.IsNullOrEmpty(asmLoc)) return null;
            var binDir = Path.GetDirectoryName(asmLoc);                              // ...\bin\Win64_Shipping_Client
            if (binDir == null) return null;
            var binParent = Directory.GetParent(binDir);                             // ...\bin
            if (binParent == null) return null;
            var crestRoot = binParent.Parent;                                        // ...\CREST
            if (crestRoot == null) return null;
            return Path.Combine(crestRoot.FullName, "crest.json");
        }
        catch
        {
            return null;
        }
    }

    private static void WriteDefault(string path)
    {
        // Default file mirrors the toggleable surface exposed in MCM
        // (MCM.UI.CrestSettings). Harmony and UIExtenderEx are intentionally
        // omitted: they're pure infrastructure, every consumer mod uses them,
        // and there's no meaningful "skip" path in source. ButterLibImplementationLoader
        // was retired in Phase H when we replaced the dynamic-loading pattern with a
        // direct SubModule reference; the flag would no-op even if present.
        // Y.22c/Y.23: defaults track the MCM "Vanilla Plus" baseline so a
        // first-launch install lands on the recommended set without needing
        // to open MCM. Anyone who wants stock-vanilla CREST behavior picks
        // the "Vanilla" preset from the upper-left dropdown in MCM.
        const string defaultJson = "{\n" +
            "  \"_comment\": \"CREST runtime configuration. Edit and relaunch the game to apply, or toggle the same checkboxes in MCM.\",\n" +
            "  \"enabled\": {\n" +
            "    \"ButterLib\": true,\n" +
            "    \"MCM\": true,\n" +
            "    \"MCMBasicImplementation\": true,\n" +
            "    \"MCMUI\": true,\n" +
            "    \"SkipIntroVideo\": true,\n" +
            "    \"MainMenuMonotone\": true,\n" +
            "    \"SuppressMainMenuMessages\": true,\n" +
            "    \"AutoUnblock\": true,\n" +
            "    \"RuntimeSelfTest\": true,\n" +
            "    \"EnableLogFiltering\": true,\n" +
            "    \"FilterSkillLogs\": true,\n" +
            "    \"FilterHeroEvents\": true,\n" +
            "    \"FilterRelationLogs\": true,\n" +
            "    \"FilterKingdomLogs\": true,\n" +
            "    \"FilterMinorBattleLogs\": true,\n" +
            "    \"FilterQuestLogs\": true,\n" +
            "    \"LogFilterScope\": \"Party only\",\n" +
            "    \"EnableFasterTime\": true,\n" +
            "    \"EnableCompanionHotswap\": true,\n" +
            "    \"EnableCampaignTweaks\": true,\n" +
            "    \"NoArrowsStuck\": true,\n" +
            "    \"LootCapturedHeroes\": true,\n" +
            "    \"LifelongLearning\": true,\n" +
            "    \"LifelongLearningMinRate\": 0.5,\n" +
            "    \"EnableAchievementsWithMods\": true,\n" +
            "    \"EnableFasterShips\": true,\n" +
            "    \"FasterShipsMultiplier\": 2.0,\n" +
            "    \"EnableReinforcements\": true,\n" +
            "    \"ReinforcementWaveMultiplier\": 1.5,\n" +
            "    \"ReinforcementIntervalSec\": -1,\n" +
            "    \"ReinforcementMaxWaves\": -1,\n" +
            "    \"EnableBattleConvergence\": true,\n" +
            "    \"BattleConvergenceRadius\": 75.0,\n" +
            "    \"BattleConvergenceMaxJoinersPerSide\": 3,\n" +
            "    \"EnableRTSCameraNavalShim\": true,\n" +
            "    \"EnableTierUnlocker\": true,\n" +
            "    \"TierUnlockerMax\": 7,\n" +
            "    \"TierUnlockerVolunteerMax\": 7\n" +
            "  }\n" +
            "}\n";
        File.WriteAllText(path, defaultJson);
    }

    /// <summary>
    /// Tiny regex-based JSON parser that handles only what our schema needs:
    /// "key": true / "key": false. We own the file format and don't need a full JSON parser
    /// (avoids taking a Newtonsoft dep in Bannerlord.Harmony, which loads before ButterLib's
    /// Newtonsoft pull-in).
    /// </summary>
    private static void ParseSimpleJson(string json, Dictionary<string, bool> dest)
    {
        var matches = Regex.Matches(json, "\"([A-Za-z_][A-Za-z0-9_]*)\"\\s*:\\s*(true|false)",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        foreach (Match m in matches)
        {
            dest[m.Groups[1].Value] = m.Groups[2].Value.Equals("true", StringComparison.OrdinalIgnoreCase);
        }
        // Phase Y.1: numeric values for sliders + hotkeys.
        // Pattern: "key": <number> -- matches integer or decimal, optional
        // sign. Sits before the quoted-string regex so 16.0 doesn't get
        // mistaken for anything else.
        var nmatches = Regex.Matches(json, "\"([A-Za-z_][A-Za-z0-9_]*)\"\\s*:\\s*(-?\\d+(?:\\.\\d+)?)",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        if (_numbers == null) _numbers = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
        foreach (Match m in nmatches)
        {
            var key = m.Groups[1].Value;
            // Don't clobber bool dict (would have already matched above)
            if (dest.ContainsKey(key)) continue;
            if (double.TryParse(m.Groups[2].Value, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var v))
                _numbers[key] = v;
        }
        // Phase W.3: also extract quoted-string values into a sibling dict so
        // the campaign-log filter scope dropdown can persist a string value.
        // Pattern: "key": "value" -- captures the inner value verbatim, no
        // escape handling beyond the obvious (we own the format).
        var smatches = Regex.Matches(json, "\"([A-Za-z_][A-Za-z0-9_]*)\"\\s*:\\s*\"([^\"]*)\"",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        if (_strings == null) _strings = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (Match m in smatches)
        {
            // Skip the _comment field (purely descriptive, would clobber anything legit).
            if (m.Groups[1].Value.Equals("_comment", StringComparison.OrdinalIgnoreCase)) continue;
            _strings[m.Groups[1].Value] = m.Groups[2].Value;
        }
    }
}
