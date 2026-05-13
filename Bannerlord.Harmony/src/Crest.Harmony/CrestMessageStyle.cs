using HarmonyLib;
using HarmonyLib.BUTR.Extensions;

using System;
using System.IO;
using System.Reflection;

using TaleWorlds.Library;

namespace Bannerlord.Harmony;

/// <summary>
/// CREST main-menu QoL: two layered behaviors on the on-screen InformationManager
/// message stack.
///
/// Layer 1 (Phase L) -- monotone color: every <c>InformationMessage</c> gets its
/// per-mod color overwritten with a single readable off-white so the upper-left
/// stops showing eye-bleeding rainbow text. Always-on; disabled via crest.json
/// "MainMenuMonotone" or env var <c>CREST_MAINMENU_MONOTONE=0</c>.
///
/// Layer 2 (Phase O) -- main-menu suppression: while the main-menu screen is
/// active (Game.CurrentGame is null), <c>InformationManager.DisplayMessage</c>
/// is short-circuited so the messages never reach the on-screen stack. The
/// text is mirrored to <c>Modules/CREST/main-menu-messages.log</c> so users
/// can still see what loaded if they want. After the user starts a campaign /
/// custom battle / loads a save, <c>Game.CurrentGame</c> is set and the
/// suppression releases -- messages display normally during gameplay.
/// Disabled via crest.json "SuppressMainMenuMessages" (default true) or env
/// var <c>CREST_SUPPRESS_MAINMENU=0</c>.
///
/// What this patches: <c>TaleWorlds.Core.InformationManager.DisplayMessage(InformationMessage)</c>
/// (older builds: <c>TaleWorlds.Library.InformationManager</c>). The same
/// prefix handles both layers in order: monotone color first, then
/// optionally returning false to skip the original display.
/// </summary>
internal static class CrestMessageStyle
{
    // Off-white at full opacity. Chosen so darker scene backgrounds are still
    // legible without the messages screaming for attention.
    private static readonly Color MonotoneColor = new Color(0.85f, 0.85f, 0.85f, 1.0f);

    private static bool _enabled = true;
    private static bool _suppressMainMenu = true;
    private static bool _patched;

    // One-shot bypass flag: when set, the next DisplayMessage call lets the
    // message through to the on-screen stack regardless of main-menu
    // suppression. Used by CREST's own user-facing confirmations
    // (CrestPatchSnapshot's "snapshot saved to..." etc) so they aren't
    // silently swallowed by the Phase O suppression while the user is
    // watching for the visual feedback.
    [System.ThreadStatic]
    private static bool _bypassNext;

    /// <summary>
    /// Mark the very next <c>InformationManager.DisplayMessage</c> call (on
    /// the same thread) as exempt from main-menu suppression. The flag is
    /// consumed by the prefix on first call, so it cannot leak to a later
    /// message. Safe to call regardless of whether suppression is enabled.
    /// </summary>
    public static void AllowNextMessage() => _bypassNext = true;
    private static Type? _gameType;
    private static System.Reflection.PropertyInfo? _gameCurrentProp;
    private static string? _logPath;

    public static void Apply(HarmonyLib.Harmony harmony)
    {
        if (_patched) return;
        _patched = true;

        if (Environment.GetEnvironmentVariable("CREST_MAINMENU_MONOTONE") == "0"
            || !CrestConfig.IsEnabled("MainMenuMonotone"))
        {
            _enabled = false;
            CrestDiag.Log(nameof(CrestMessageStyle), "monotone disabled via crest.json or env var");
        }

        // Phase O: suppress on-screen display while on the main menu, mirror to log.
        if (Environment.GetEnvironmentVariable("CREST_SUPPRESS_MAINMENU") == "0"
            || !CrestConfig.IsEnabled("SuppressMainMenuMessages"))
        {
            _suppressMainMenu = false;
            CrestDiag.Log(nameof(CrestMessageStyle), "main-menu suppression disabled");
        }

        // Resolve TaleWorlds.Core.Game.Current property for "are we on main menu?" check.
        // Game.Current is null until the user starts a campaign / custom battle / loads
        // a save. Using reflection so we don't take a hard project dependency on Core
        // at compile time.
        try
        {
            _gameType = AccessTools2.TypeByName("TaleWorlds.Core.Game");
            if (_gameType != null)
                _gameCurrentProp = _gameType.GetProperty("Current", BindingFlags.Public | BindingFlags.Static);
        }
        catch (Exception ex) { CrestDiag.LogCaught(nameof(CrestMessageStyle), "resolve Game.Current", ex); }

        // Resolve the log path for mirrored main-menu messages: Modules/CREST/main-menu-messages.log
        // Anchor on this assembly's location so the path works regardless of the
        // process CWD (launcher, game, standalone, etc.).
        try
        {
            var asmLoc = typeof(CrestMessageStyle).Assembly.Location;
            if (!string.IsNullOrEmpty(asmLoc))
            {
                var binDir = Path.GetDirectoryName(asmLoc);
                if (binDir != null)
                {
                    var binParent = Directory.GetParent(binDir);
                    var crestRoot = binParent?.Parent;
                    if (crestRoot != null)
                        _logPath = Path.Combine(crestRoot.FullName, "main-menu-messages.log");
                }
            }
        }
        catch { /* best effort */ }

        if (!_enabled && !_suppressMainMenu) return; // both layers off, no point patching

        // InformationManager lived at TaleWorlds.Core for some game versions
        // and TaleWorlds.Library for others. Try both, in order, and log which
        // one bound. AccessTools2.TypeByName silently returns null when the
        // type is missing, so iterating is cheap.
        var candidates = new[]
        {
            "TaleWorlds.Library.InformationManager",
            "TaleWorlds.Core.InformationManager",
        };

        try
        {
            Type? infoManagerType = null;
            string? boundName = null;
            foreach (var n in candidates)
            {
                var t = AccessTools2.TypeByName(n);
                if (t != null) { infoManagerType = t; boundName = n; break; }
            }
            if (infoManagerType == null)
            {
                CrestDiag.Log(nameof(CrestMessageStyle), "no InformationManager type found in any of: " + string.Join(", ", candidates));
                return;
            }

            // Bind DisplayMessage by parameter type (InformationMessage). Use
            // GetMethods rather than the colon-string lookup so we definitely
            // find the right overload.
            MethodInfo? displayMessage = null;
            foreach (var m in infoManagerType.GetMethods(BindingFlags.Public | BindingFlags.Static))
            {
                if (m.Name != "DisplayMessage") continue;
                var ps = m.GetParameters();
                if (ps.Length == 1 && ps[0].ParameterType.Name == "InformationMessage")
                {
                    displayMessage = m;
                    break;
                }
            }
            if (displayMessage == null)
            {
                CrestDiag.Log(nameof(CrestMessageStyle), "DisplayMessage(InformationMessage) not found on " + boundName);
                return;
            }

            harmony.Patch(displayMessage,
                prefix: new HarmonyMethod(typeof(CrestMessageStyle), nameof(DisplayMessagePrefix)));
            CrestDiag.Log(nameof(CrestMessageStyle), "patched " + boundName + ".DisplayMessage(InformationMessage)");
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(nameof(CrestMessageStyle), "Apply", ex);
        }
    }

    // Prefix runs before DisplayMessage queues the message. Parameter MUST be
    // named `message` to match the original method's parameter name -- Harmony
    // binds prefix args by name. Returning false skips the original method
    // (suppressing on-screen display). Returning true (default) lets the
    // original run normally.
    //
    // Three layers in order:
    //   (1) overwrite color to monotone if enabled,
    //   (2) [Phase W.12] campaign-log filter on the on-screen toast: classify
    //       the message text against patterns mapped to the same six buckets
    //       used by CrestCampaignLogFilter; suppress if the bucket is off,
    //   (3) on main menu, mirror text to log file and suppress on-screen.
    private static bool DisplayMessagePrefix(InformationMessage message)
    {
        if (message == null) return true;

        // Layer 1: monotone color
        if (_enabled)
        {
            try { message.Color = MonotoneColor; }
            catch { /* property shape may have changed; fall through */ }
        }

        // Layer 2: text-pattern bucket + scope filter (Phase W.12 / W.14 / W.15).
        // CrestCampaignLogFilter already filters at NewLogEntryAdded time, but
        // most events fire BOTH a LogEntry AND a DisplayMessage independently,
        // so the on-screen toasts slip through. Mirror the same filtering here
        // by classifying the localized text against substring patterns.
        //
        // Phase W.15 semantics (rewritten from W.14):
        //   None         -> only the per-bucket toggles apply.
        //   All          -> every classified chatter message is suppressed,
        //                   regardless of whether its bucket is on.
        //   Party only / -> WHITELIST OVERRIDE for player-related chatter:
        //   Clan only       messages mentioning the player's hero / party /
        //   Kingdom only    clan / kingdom name pass through EVEN IF their
        //                   bucket is muted. Other classified chatter still
        //                   obeys the bucket toggle.
        //
        // Daily Gold Change and other unclassified messages are unaffected
        // by scope (ClassifyToastText returns null and we fall through).
        // Phase W.25: filter is gated on master AND on whether any bucket /
        // scope setting could plausibly suppress anything. If nothing can,
        // skip the pattern matching entirely -- saves work on every toast
        // when the user has all-permissive settings.
        if (CrestConfig.IsEnabled("EnableLogFiltering", defaultValue: false) && CouldSuppressAnything())
        {
            try
            {
                var text = message.Information ?? string.Empty;
                if (text.Length > 0)
                {
                    // Phase W.25: lowercase once and share between classifier
                    // and anchor-mention check (each used to do its own
                    // ToLowerInvariant -- 2 string allocs per call).
                    var lowerText = text.ToLowerInvariant();
                    var bucket = ClassifyToastTextLower(lowerText);
                    var classified = bucket != null;

                    // Phase Z.4: parse scope to enum once instead of running
                    // 6 OrdinalIgnoreCase string.Equals checks per message.
                    // Inside scope-aware branches, TextMentionsPlayerAnchorLower
                    // also takes the enum so it stops re-comparing the string.
                    var scope = ParseScope(CrestConfig.GetString("LogFilterScope", "None"));

                    switch (scope)
                    {
                        case LogScope.All:
                            if (classified) return false;
                            break;
                        case LogScope.None:
                            if (classified && !CrestConfig.IsEnabled(bucket!, defaultValue: true))
                                return false;
                            break;
                        default:
                            // Party / Clan / Kingdom: classified messages are
                            // suppressed UNLESS they mention the player anchor.
                            if (classified && !TextMentionsPlayerAnchorLower(lowerText, scope))
                                return false;
                            break;
                    }
                }
            }
            catch { /* never let filter logic block a message */ }
        }

        // Layer 3: main-menu suppression
        if (_suppressMainMenu && IsOnMainMenu())
        {
            // One-shot bypass for CREST's own user-facing confirmations.
            // Consumed once and cleared so it can't leak forward.
            if (_bypassNext)
            {
                _bypassNext = false;
                return true; // let the on-screen display run
            }

            try
            {
                AppendToLog(message);
            }
            catch { /* never block on log write failure */ }
            return false; // skip original DisplayMessage -> message never reaches on-screen stack
        }

        return true;
    }

    // Caches for additional "are we in a session" probes, resolved lazily on
    // first call. We can't take compile-time refs to TaleWorlds.MountAndBlade
    // (Crest.Harmony loads first and that assembly may not be on the probe
    // path yet), so reflection-only.
    private static System.Reflection.PropertyInfo? _missionCurrentProp;
    private static System.Reflection.PropertyInfo? _campaignCurrentProp;
    private static bool _diagDumped;
    private static bool _additionalProbesResolved;

    private static void ResolveAdditionalProbes()
    {
        if (_additionalProbesResolved) return;
        _additionalProbesResolved = true;
        try
        {
            var missionType = AccessTools2.TypeByName("TaleWorlds.MountAndBlade.Mission");
            if (missionType != null)
                _missionCurrentProp = missionType.GetProperty("Current",
                    System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static);
        }
        catch { }
        try
        {
            var campaignType = AccessTools2.TypeByName("TaleWorlds.CampaignSystem.Campaign");
            if (campaignType != null)
                _campaignCurrentProp = campaignType.GetProperty("Current",
                    System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static);
        }
        catch { }
    }

    private static bool IsOnMainMenu()
    {
        // Phase O.2: Game.Current was null on the main menu in v1.4.1, but
        // v1.4.2 initializes a placeholder Game while still on the main menu
        // (likely so the loading splash + initial menu have a Game.Service
        // container available). The original single-property probe broke
        // silently -- community-mod chat reappeared.
        //
        // New signal: Mission.Current is null (no active battle / siege /
        // arena / encounter mission) AND Campaign.Current is null (no
        // campaign loaded / save active). Both null = no session of any
        // kind = main menu (or a brief transition during loading where
        // suppression is also fine).
        //
        // Game.Current is intentionally NOT consulted any more.
        ResolveAdditionalProbes();
        try
        {
            var missionNull  = true;
            var campaignNull = true;
            try { if (_missionCurrentProp  != null) missionNull  = _missionCurrentProp.GetValue(null)  == null; } catch { }
            try { if (_campaignCurrentProp != null) campaignNull = _campaignCurrentProp.GetValue(null) == null; } catch { }

            // First-call diagnostic for triage if this STILL fails.
            if (!_diagDumped)
            {
                _diagDumped = true;
                var gameDbg = "(unprobed)";
                try { if (_gameCurrentProp != null) gameDbg = (_gameCurrentProp.GetValue(null) == null) ? "null" : "not-null"; } catch { }
                CrestDiag.Log(nameof(CrestMessageStyle),
                    "first DisplayMessage probe -- Mission.Current=" + (missionNull ? "null" : "not-null") +
                    ", Campaign.Current=" + (campaignNull ? "null" : "not-null") +
                    " (Game.Current=" + gameDbg + ", informational only)");
            }

            // If both Mission and Campaign probes failed to resolve at all
            // (both still default true), we have no signal -- fail open and
            // let the message through. Better to leak a few main-menu lines
            // than to silently suppress every InformationMessage in-game.
            if (_missionCurrentProp == null && _campaignCurrentProp == null) return false;

            return missionNull && campaignNull;
        }
        catch
        {
            return false;
        }
    }

    // Phase W.12: classify an on-screen InformationManager toast by substring
    // patterns into the same six buckets CrestCampaignLogFilter uses. Returns
    // the bucket name (e.g. "FilterMinorBattleLogs") if the text matches, or
    // null if the text doesn't match any classified pattern (unfiltered).
    //
    // Why text-pattern instead of LogEntry typing: most TaleWorlds campaign
    // events fire both a LogEntry (which goes to the encyclopedia/hero log
    // and which CrestCampaignLogFilter intercepts) AND a separate
    // InformationMessage display (which renders the on-screen toast and
    // bypasses NewLogEntryAdded entirely). To mute the toast we have to
    // recognize it independently here.
    //
    // Patterns are matched via case-insensitive Contains. They're written
    // against the English game strings; if the user's game is in another
    // locale the patterns won't match and the toast passes through. That's
    // acceptable for a v1 -- a future iteration can hook the localization
    // system to do canonical-id matching instead.
    //
    // Whitelist: text containing "Daily Gold Change" is intentionally NOT
    // classified into any bucket so it always passes through. Same for
    // anything not matching a known pattern (fail-open).
    private static readonly (string Pattern, string Bucket)[] _textPatterns = new[]
    {
        // Minor world events (raids, prisoners, defenses)
        ("has been taken prisoner by",      "FilterMinorBattleLogs"),
        ("has been released after",         "FilterMinorBattleLogs"),
        ("is raided by",                    "FilterMinorBattleLogs"),
        (" has been raided",                "FilterMinorBattleLogs"),
        ("'s Party is defending",           "FilterMinorBattleLogs"),
        (" Party is defending",             "FilterMinorBattleLogs"),
        (" is defending ",                  "FilterMinorBattleLogs"),
        ("Coastal Patrol is defending",     "FilterMinorBattleLogs"),

        // Quests / issues / tournaments
        ("tournament has started in",       "FilterQuestLogs"),
        ("A new tournament has started",    "FilterQuestLogs"),
        (" has won the tournament",         "FilterQuestLogs"),
        ("issue has started",               "FilterQuestLogs"),
        ("issue is complete",               "FilterQuestLogs"),
        ("Quest completed:",                "FilterQuestLogs"),

        // Skill / level-up
        (" has gained the ",                "FilterSkillLogs"),
        ("gained a skill point in",         "FilterSkillLogs"),
        (" reached level ",                 "FilterSkillLogs"),
        (" has gained a perk",              "FilterSkillLogs"),
        (" is now level ",                  "FilterSkillLogs"),
        (" and is now ",                    "FilterSkillLogs"),

        // Hero life events
        (" has died",                       "FilterHeroEvents"),
        (" was born to ",                   "FilterHeroEvents"),
        (" came of age",                    "FilterHeroEvents"),
        (" got married",                    "FilterHeroEvents"),

        // Relation changes
        (" likes you more",                 "FilterRelationLogs"),
        (" likes you less",                 "FilterRelationLogs"),
        ("Your relation with",              "FilterRelationLogs"),

        // Kingdom politics + mercenary contracts + clan defections
        (" has declared war on",            "FilterKingdomLogs"),
        (" made peace with",                "FilterKingdomLogs"),
        (" joined the kingdom of",          "FilterKingdomLogs"),
        (" left the kingdom of",            "FilterKingdomLogs"),
        ("policy has been enacted",         "FilterKingdomLogs"),
        ("have contracted to fight alongside", "FilterKingdomLogs"),
        ("clan has joined the",             "FilterKingdomLogs"),
        ("clan has left the",               "FilterKingdomLogs"),
        ("clan has defected to",            "FilterKingdomLogs"),
        (" became a vassal of",             "FilterKingdomLogs"),
        (" no longer fights for",           "FilterKingdomLogs"),
    };

    // Phase W.17 perf: pre-lowercase the patterns at static init so the
    // hot loop can do case-sensitive Contains (much cheaper than
    // OrdinalIgnoreCase IndexOf for short strings).
    private static readonly (string LowerPattern, string Bucket)[] _lowerTextPatterns = BuildLowerPatterns();
    private static readonly string _whitelistDailyGoldLower = "daily gold change";
    private static (string, string)[] BuildLowerPatterns()
    {
        var src = _textPatterns;
        var dst = new (string, string)[src.Length];
        for (int i = 0; i < src.Length; i++)
            dst[i] = (src[i].Pattern.ToLowerInvariant(), src[i].Bucket);
        return dst;
    }

    // Phase W.25: precomputed bucket-key list mirrors _lowerTextPatterns.
    // Used by CouldSuppressAnything to know, without scanning the message,
    // whether the current crest.json state could possibly result in any
    // suppression. If not, the toast filter early-exits.
    private static readonly string[] _allBucketKeys = new[]
    {
        "FilterMinorBattleLogs",
        "FilterQuestLogs",
        "FilterSkillLogs",
        "FilterHeroEvents",
        "FilterRelationLogs",
        "FilterKingdomLogs",
    };

    // Returns true when the current scope+bucket configuration could result
    // in at least one classified message being suppressed. When false, the
    // toast filter has nothing to do and can early-exit before the more
    // expensive pattern-matching work.
    private static bool CouldSuppressAnything()
    {
        var scope = CrestConfig.GetString("LogFilterScope", "None");
        // Any non-None scope can suppress (All hides everything classified;
        // Party/Clan/Kingdom hides classified-not-about-player).
        if (!string.Equals(scope, "None", StringComparison.OrdinalIgnoreCase)) return true;
        // Scope=None: only bucket toggles matter. If at least one is off
        // (suppress), some classified messages can be hidden.
        for (int i = 0; i < _allBucketKeys.Length; i++)
            if (!CrestConfig.IsEnabled(_allBucketKeys[i], defaultValue: true)) return true;
        return false;
    }

    private static string? ClassifyToastTextLower(string lower)
    {
        // Whitelist: financial signal must always show.
        if (lower.IndexOf(_whitelistDailyGoldLower, StringComparison.Ordinal) >= 0)
            return null;

        for (int i = 0; i < _lowerTextPatterns.Length; i++)
        {
            if (lower.IndexOf(_lowerTextPatterns[i].LowerPattern, StringComparison.Ordinal) >= 0)
                return _lowerTextPatterns[i].Bucket;
        }
        return null;
    }

    // Phase W.14/W.16/W.25: cache player-anchor name strings (pre-lowercased)
    // so the toast filter can do scope-based matching without re-resolving
    // Hero.MainHero or re-lowercasing names per call. Lock-free fast path
    // uses Volatile reads on the timestamp; only one thread does reflection
    // work via Interlocked.CompareExchange on the refreshing flag.
    private static volatile string? _anchorMainHeroNameLower;
    private static volatile string? _anchorMainPartyNameLower;
    private static volatile string? _anchorClanNameLower;
    private static volatile string? _anchorKingdomNameLower;
    private static long _anchorResolvedAtTicks;          // ticks (UTC); 0 = unresolved
    private static int  _anchorRefreshingFlag;           // 0 idle, 1 in-progress (Interlocked)
    private static readonly long AnchorFreshnessTicks = TimeSpan.TicksPerSecond * 5;

    private static void RefreshPlayerAnchors()
    {
        var now = DateTime.UtcNow.Ticks;
        var resolved = System.Threading.Volatile.Read(ref _anchorResolvedAtTicks);
        if (resolved != 0 && now - resolved < AnchorFreshnessTicks) return;  // hot path: lock-free

        // Try to claim the refresh slot. If another thread is already
        // refreshing, return immediately and let it finish; the cached
        // values stay readable.
        if (System.Threading.Interlocked.CompareExchange(ref _anchorRefreshingFlag, 1, 0) != 0) return;
        try
        {
            var heroT  = AccessTools2.TypeByName("TaleWorlds.CampaignSystem.Hero");
            var partyT = AccessTools2.TypeByName("TaleWorlds.CampaignSystem.Party.MobileParty");
            var clanT  = AccessTools2.TypeByName("TaleWorlds.CampaignSystem.Clan");

            var mainHero  = heroT?.GetProperty("MainHero",  BindingFlags.Public | BindingFlags.Static)?.GetValue(null);
            var mainParty = partyT?.GetProperty("MainParty", BindingFlags.Public | BindingFlags.Static)?.GetValue(null);
            var playerClan= clanT?.GetProperty("PlayerClan", BindingFlags.Public | BindingFlags.Static)?.GetValue(null);
            var playerKingdom = playerClan != null ? SafeMember(playerClan, "Kingdom") : null;

            _anchorMainHeroNameLower  = SafeNameLowerOf(mainHero);
            _anchorMainPartyNameLower = SafeNameLowerOf(mainParty);
            _anchorClanNameLower      = SafeNameLowerOf(playerClan);
            _anchorKingdomNameLower   = SafeNameLowerOf(playerKingdom);

            System.Threading.Volatile.Write(ref _anchorResolvedAtTicks, now);
        }
        catch { /* leave whatever was already cached */ }
        finally
        {
            System.Threading.Interlocked.Exchange(ref _anchorRefreshingFlag, 0);
        }
    }

    private static string? SafeNameLowerOf(object? obj)
    {
        var s = SafeNameOf(obj);
        return string.IsNullOrEmpty(s) ? null : s!.ToLowerInvariant();
    }

    private static object? SafeMember(object obj, string name)
    {
        try
        {
            var t = obj.GetType();
            var p = t.GetProperty(name, BindingFlags.Public | BindingFlags.Instance);
            return p?.GetValue(obj);
        }
        catch { return null; }
    }

    private static string? SafeNameOf(object? obj)
    {
        if (obj == null) return null;
        try
        {
            var t = obj.GetType();
            // Try Name, then ToString.
            var nameProp = t.GetProperty("Name", BindingFlags.Public | BindingFlags.Instance);
            if (nameProp != null)
            {
                var v = nameProp.GetValue(obj);
                if (v != null)
                {
                    var s = v.ToString();
                    if (!string.IsNullOrEmpty(s)) return s;
                }
            }
            var s2 = obj.ToString();
            return string.IsNullOrEmpty(s2) ? null : s2;
        }
        catch { return null; }
    }

    // Phase Z.4: pre-parsed scope. Avoids running 6 OrdinalIgnoreCase
    // string.Equals checks per message inside the toast filter hot path.
    private enum LogScope : byte { None, All, Party, Clan, Kingdom }

    private static LogScope ParseScope(string? raw)
    {
        if (string.IsNullOrEmpty(raw)) return LogScope.None;
        // Length-first matching avoids most full equals calls.
        if (raw!.Length == 4)
        {
            if (string.Equals(raw, "None", StringComparison.OrdinalIgnoreCase)) return LogScope.None;
            if (string.Equals(raw, "Clan", StringComparison.OrdinalIgnoreCase)) return LogScope.Clan;
        }
        if (raw.Length == 3 && string.Equals(raw, "All", StringComparison.OrdinalIgnoreCase)) return LogScope.All;
        if (raw.Length == 5 && string.Equals(raw, "Party", StringComparison.OrdinalIgnoreCase)) return LogScope.Party;
        if (raw.Length == 7 && string.Equals(raw, "Kingdom", StringComparison.OrdinalIgnoreCase)) return LogScope.Kingdom;
        // Long forms used by the MCM dropdown.
        if (string.Equals(raw, "Party only",   StringComparison.OrdinalIgnoreCase)) return LogScope.Party;
        if (string.Equals(raw, "Clan only",    StringComparison.OrdinalIgnoreCase)) return LogScope.Clan;
        if (string.Equals(raw, "Kingdom only", StringComparison.OrdinalIgnoreCase)) return LogScope.Kingdom;
        return LogScope.None;
    }

    private static bool TextMentionsPlayerAnchorLower(string lower, LogScope scope)
    {
        // Caller already lowercased text. Anchor names are pre-lowercased
        // when refreshed, so each check is one Ordinal IndexOf -- no
        // per-call ToLowerInvariant on either side.
        RefreshPlayerAnchors();

        // Inline mentions check (no closure allocation).
        bool MentionsName(string? n) =>
            !string.IsNullOrEmpty(n) && lower.IndexOf(n!, StringComparison.Ordinal) >= 0;

        switch (scope)
        {
            case LogScope.Party:
                return MentionsName(_anchorMainHeroNameLower) || MentionsName(_anchorMainPartyNameLower);
            case LogScope.Clan:
                return MentionsName(_anchorMainHeroNameLower) || MentionsName(_anchorMainPartyNameLower) ||
                       MentionsName(_anchorClanNameLower);
            case LogScope.Kingdom:
                return MentionsName(_anchorMainHeroNameLower) || MentionsName(_anchorMainPartyNameLower) ||
                       MentionsName(_anchorClanNameLower)     || MentionsName(_anchorKingdomNameLower);
            default:
                // None / All: this overload is only invoked for the player-anchor
                // branch (Party/Clan/Kingdom), but be permissive otherwise.
                return true;
        }
    }

    private static void AppendToLog(InformationMessage message)
    {
        if (_logPath == null) return;
        string text;
        try { text = message.Information ?? string.Empty; }
        catch { text = string.Empty; }
        if (string.IsNullOrEmpty(text)) return;

        var line = $"[{DateTime.Now:HH:mm:ss.fff}] {text}{Environment.NewLine}";
        try
        {
            File.AppendAllText(_logPath, line);
        }
        catch
        {
            // Best-effort. If logging fails the message is just lost; we still
            // want to suppress display because that was the point.
        }
    }
}
