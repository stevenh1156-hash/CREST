using HarmonyLib;
using HarmonyLib.BUTR.Extensions;

using System;
using System.Collections.Generic;
using System.Reflection;

namespace Bannerlord.Harmony;

/// <summary>
/// Phase W -- IDontCare-lite. Suppresses categories of campaign-log spam at
/// the engine's single-funnel point so users don't have to ship a separate
/// Nexus mod just to mute "Hero X levelled up Athletics" every five seconds.
///
/// Architecture: Bannerlord routes every campaign log entry through
/// <c>TaleWorlds.CampaignSystem.CampaignInformationManager.NewLogEntryAdded(LogEntry)</c>.
/// Each subclass of <c>LogEntry</c> describes one event class (a hero died,
/// a skill went up, a kingdom declared war, etc). We patch that one method
/// with a prefix that classifies the entry's runtime type into ~6 buckets
/// and returns <c>false</c> when the matching bucket flag in
/// <c>crest.json</c> is set false. Each bucket has its own MCM checkbox in
/// <c>CrestSettings</c>.
///
/// Phase W.4 master toggle: the entire filter is gated on
/// <c>EnableLogFiltering</c>. When that flag is false (the default), this
/// prefix early-returns true on every call -- the patch is bound but
/// inert. Users opt in by flipping the IsToggle=true master in MCM, which
/// also reveals the per-category sub-toggles in the UI.
///
/// Why patch <c>NewLogEntryAdded</c> rather than <c>InformationManager.DisplayMessage</c>:
/// some campaign events also write to the in-game encyclopedia / hero log /
/// other side panels. Suppressing only the on-screen toast (Phase O's path)
/// would leave the entry rattling around the rest of the campaign systems.
/// Suppressing at <c>NewLogEntryAdded</c> filters every consumer at once.
///
/// The patch applies LAZILY at <c>OnBeforeInitialModuleScreenSetAsRoot</c>
/// time -- <c>TaleWorlds.CampaignSystem.dll</c> isn't loaded when
/// <c>Crest.Harmony.SubModule.OnSubModuleLoad</c> fires. The lazy hook is
/// already there for <c>ValidateLoadOrder</c>; we just piggyback.
/// </summary>
internal static class CrestCampaignLogFilter
{
    private const string Source = nameof(CrestCampaignLogFilter);

    // Classification by LogEntry subclass NAME (not full namespace) so we
    // match across moves between TaleWorlds.CampaignSystem.LogEntries vs
    // .ChangeOfStateLogEntries vs .Sandbox.LogEntries etc. Keys are class
    // simple-names; values are bucket names that match crest.json flags.
    //
    // NOT exhaustive -- there are ~150 LogEntry subclasses in the campaign
    // system. We cover the visibly chatty ones; everything not in this map
    // passes through unfiltered. Add entries as new spam sources surface.
    private static readonly Dictionary<string, string> _classification = new(StringComparer.OrdinalIgnoreCase)
    {
        // Skill / experience
        { "SkillLevelChangedLogEntry",                 "FilterSkillLogs" },
        { "HeroGainedSkillLogEntry",                   "FilterSkillLogs" },
        { "PlayerLeveledUpLogEntry",                   "FilterSkillLogs" },
        { "PerkSelectedLogEntry",                      "FilterSkillLogs" },

        // Hero life events
        { "HeroDiedLogEntry",                          "FilterHeroEvents" },
        { "HeroComesOfAgeLogEntry",                    "FilterHeroEvents" },
        { "HeroBornLogEntry",                          "FilterHeroEvents" },
        { "HeroGotMarriedLogEntry",                    "FilterHeroEvents" },
        { "ChildBornLogEntry",                         "FilterHeroEvents" },
        { "ChildBornToHeroLogEntry",                   "FilterHeroEvents" },

        // Relation changes
        { "ChangeRelationLogEntry",                    "FilterRelationLogs" },
        { "HeroRelationChangedLogEntry",               "FilterRelationLogs" },

        // Kingdom / faction politics
        { "DeclareWarLogEntry",                        "FilterKingdomLogs" },
        { "MakePeaceLogEntry",                         "FilterKingdomLogs" },
        { "KingdomCreatedLogEntry",                    "FilterKingdomLogs" },
        { "KingdomDecisionConcludedLogEntry",          "FilterKingdomLogs" },
        { "ClanChangedKingdomLogEntry",                "FilterKingdomLogs" },
        { "PolicyChangedLogEntry",                     "FilterKingdomLogs" },
        { "ChangeKingdomLogEntry",                     "FilterKingdomLogs" },
        { "BannerlordEra_KingdomCreatedLogEntry",      "FilterKingdomLogs" },

        // Minor world events (looters/bandits, raids on villages, prisoner
        // status changes, defenses). Renamed in MCM label to "Minor world
        // events" to reflect the broader scope; flag name stays as-is for
        // crest.json round-trip compat.
        { "LooterEncounterDefeatedLogEntry",                   "FilterMinorBattleLogs" },
        { "BanditEncounterDefeatedLogEntry",                   "FilterMinorBattleLogs" },
        { "MinorEncounterDefeatedLogEntry",                    "FilterMinorBattleLogs" },
        { "VillageRaidedLogEntry",                             "FilterMinorBattleLogs" },
        { "VillageBeingRaidedLogEntry",                        "FilterMinorBattleLogs" },
        { "VillageStateChangedLogEntry",                       "FilterMinorBattleLogs" },
        { "VillageBecameNormalLogEntry",                       "FilterMinorBattleLogs" },
        // Prisoner taken/released chatter -- particularly noisy on the world map
        { "HeroPrisonerTakenLogEntry",                         "FilterMinorBattleLogs" },
        { "HeroPrisonerReleasedLogEntry",                      "FilterMinorBattleLogs" },
        { "HeroPrisonerReleasedByEndingPartyLogEntry",         "FilterMinorBattleLogs" },
        { "EndCaptivityLogEntry",                              "FilterMinorBattleLogs" },
        // Party defending a settlement (NPC parties, mostly)
        { "PartyDefendingSettlementLogEntry",                  "FilterMinorBattleLogs" },
        { "DefenderPartyJoinedSettlementLogEntry",             "FilterMinorBattleLogs" },

        // Quests / issues / tournaments
        { "IssueStartedLogEntry",                              "FilterQuestLogs" },
        { "IssueByPlayerCompletedLogEntry",                    "FilterQuestLogs" },
        { "QuestFinishedLogEntry",                             "FilterQuestLogs" },
        { "TrackQuestLogEntry",                                "FilterQuestLogs" },
        { "TournamentStartedLogEntry",                         "FilterQuestLogs" },
        { "TournamentWonLogEntry",                             "FilterQuestLogs" },

        // NOT classified (intentionally always visible, never filtered):
        //   IncomeChangeLogEntry / DailyTickLogEntry / "Daily Gold Change: N"
        //   -- user request: useful financial signal, must always show.
    };

    // Phase Z.4 P1-9: lazy-populated Type-keyed cache mirroring _classification.
    // _classification is the source of truth (hand-written string keys); on
    // first encounter of each runtime LogEntry Type, we look up its Name once
    // and cache the bucket-or-null answer. Subsequent NewLogEntryAdded calls
    // hit the Type-keyed cache directly -- no .GetType().Name string getter,
    // no case-insensitive hash on the string. Concurrent for thread-safety
    // with the daily-tick fan-out that fires events from multiple threads.
    private static readonly System.Collections.Concurrent.ConcurrentDictionary<Type, string?> _typeBucketCache = new();

    private static string? ClassifyByType(Type t)
    {
        return _typeBucketCache.GetOrAdd(t, type =>
            _classification.TryGetValue(type.Name, out var bucket) ? bucket : null);
    }

    private static bool _patched;

    public static void TryApply(HarmonyLib.Harmony harmony)
    {
        if (_patched) return;

        try
        {
            var targetType = AccessTools2.TypeByName("TaleWorlds.CampaignSystem.CampaignInformationManager");
            if (targetType == null)
            {
                // Campaign system not loaded yet -- quietly bail. We're called
                // at OnBeforeInitialModuleScreenSetAsRoot which fires after
                // SandBoxCore initializes, so this should be a one-time
                // version-shift signal not a routine condition.
                CrestDiag.LogTypeNotFound(Source, "TaleWorlds.CampaignSystem.CampaignInformationManager");
                return;
            }

            // The LogEntry parameter name and exact arity can drift between
            // game versions. Bind by name + parameter count rather than
            // assuming a specific signature.
            //
            // v1.4.2 finding: NewLogEntryAdded is INTERNAL (not public), so
            // the original public-only flag set returned no matches and the
            // patch silently skipped binding. Phase W.8 enumerated the type
            // via Mono.Cecil and confirmed the actual signature is:
            //   internal void NewLogEntryAdded(LogEntry log)
            // Searching public+nonpublic instance methods catches both the
            // internal v1.4.2 form and any future public refactor.
            MethodInfo? target = null;
            foreach (var m in targetType.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance))
            {
                if (m.Name != "NewLogEntryAdded") continue;
                if (m.GetParameters().Length != 1) continue;
                target = m; break;
            }
            if (target == null)
            {
                CrestDiag.Log(Source, "NewLogEntryAdded(arity-1) not found on CampaignInformationManager -- skipping filter");
                return;
            }

            harmony.Patch(target,
                prefix: new HarmonyMethod(typeof(CrestCampaignLogFilter), nameof(NewLogEntryAddedPrefix)));
            _patched = true;
            CrestDiag.Log(Source, "patched CampaignInformationManager.NewLogEntryAdded -- " + _classification.Count + " classified entry types across 6 buckets");
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "TryApply", ex);
        }
    }

    // Phase W.4 diagnostic rate-limiter: we don't want every single LogEntry
    // dropping a line into runtime.log when CrestConfig diagnostics is on.
    // Log the FIRST suppression of each (typeName, scope, decision) tuple,
    // then stay quiet. This is enough to validate the filter is doing what
    // the user expects without flooding the file.
    private static readonly HashSet<string> _diagDecisionsSeen = new(StringComparer.OrdinalIgnoreCase);
    private const int DiagBudgetMax = 200;

    private static void DiagOnce(string key, Func<string> messageBuilder)
    {
        if (_diagDecisionsSeen.Count >= DiagBudgetMax) return;
        if (!_diagDecisionsSeen.Add(key)) return;
        try { CrestDiag.Log(Source, messageBuilder()); } catch { }
    }

    /// <summary>
    /// Prefix runs before the engine routes the LogEntry to its consumers.
    /// Returns false to skip the original (suppresses), true to let it run.
    /// Parameter name MUST match the original method's parameter (Harmony
    /// binds prefix args by name). Phase W.10 fix: v1.4.2's parameter is
    /// named <c>log</c>, not <c>logEntry</c>. The Cecil enumeration in
    /// phase-w8 confirmed:
    ///   internal void NewLogEntryAdded(LogEntry log)
    /// If a future version renames it again, the prefix will throw at
    /// patch time and TryApply's catch block will log + bail (filter is
    /// inert until the binding is fixed).
    /// </summary>
    private static bool NewLogEntryAddedPrefix(object log)
    {
        if (log == null) return true;
        try
        {
            // Phase W.4: master gate. If filtering is off, every entry passes
            // straight through. The MCM master toggle is wired so that turning
            // it OFF also hides every sub-option in the UI.
            if (!CrestConfig.IsEnabled("EnableLogFiltering", defaultValue: false))
            {
                return true;
            }

            // Phase Z.4 P1-9: cache LogEntry classification by Type instead
            // of looking up by .GetType().Name (string getter + ordinal-ignore-case
            // hash) on every campaign event. The Type identity is stable for
            // the lifetime of the AppDomain so the cache never has to invalidate.
            // typeName is still computed lazily for diagnostic messages only --
            // not on the hot path.
            var entryType = log.GetType();
            var bucket = ClassifyByType(entryType);

            // Phase W.3: scope filter (None / All / Party only / Clan only / Kingdom only)
            // applies BEFORE category gating. If scope says "irrelevant",
            // suppress regardless of category. If scope says "relevant" or
            // "None" (no filter), fall through to category check.
            var scope = CrestConfig.GetString("LogFilterScope", "None");
            if (!string.Equals(scope, "None", StringComparison.OrdinalIgnoreCase))
            {
                // Use entryType.Name for the diag message (only computed if the
                // DiagOnce throttle hasn't seen this combination yet).
                if (!IsRelevantAtScope(log, entryType.Name, scope))
                {
                    DiagOnce("scope-suppress|" + entryType.Name + "|" + scope,
                        () => "scope-suppress: " + entryType.Name + " hidden under scope='" + scope + "'");
                    return false;
                }
                else
                {
                    DiagOnce("scope-pass|" + entryType.Name + "|" + scope,
                        () => "scope-pass:    " + entryType.Name + " kept under scope='" + scope + "'");
                }
            }

            if (bucket == null) return true;
            // Default true: any unset flag = let the message through.
            if (CrestConfig.IsEnabled(bucket, defaultValue: true)) return true;
            DiagOnce("bucket-suppress|" + entryType.Name + "|" + bucket,
                () => "bucket-suppress: " + entryType.Name + " hidden under bucket='" + bucket + "'");
            return false;  // suppress
        }
        catch (Exception ex)
        {
            // If anything blows up, never block the original call -- a bug
            // in our filter must not cost the user campaign log entries.
            DiagOnce("prefix-threw|" + ex.GetType().Name,
                () => "prefix threw: " + ex.GetType().Name + " " + ex.Message);
            return true;
        }
    }

    /// <summary>
    /// Returns true when the LogEntry references the player's
    /// hero / party / clan / kingdom at the requested scope level.
    /// Walks the entry's public properties via reflection (each LogEntry
    /// subclass exposes its referenced entities differently -- e.g.
    /// <c>HeroDiedLogEntry.DeadHero</c>, <c>VillageRaidedLogEntry.RaiderParty</c>,
    /// <c>ChangeRelationLogEntry.AffectedHero</c>) so we don't need a per-class
    /// switch table.
    /// </summary>
    private static bool IsRelevantAtScope(object logEntry, string typeName, string scope)
    {
        // "All" scope: hide every entry that has ANY hero/party/clan/kingdom
        // ref at all. Entries with no entity refs (Daily Gold Change,
        // tick events, generic financial summaries) pass through -- those are
        // the "always-visible" signals the user wants to keep.
        var refs = ExtractEntityRefs(logEntry);

        if (string.Equals(scope, "All", StringComparison.OrdinalIgnoreCase))
        {
            return refs.IsEmpty;
        }

        // Resolve player's anchor entities. If MainHero/MainParty haven't
        // been initialized yet (e.g. during a campaign load), fail open so
        // the user doesn't lose entries during the brief startup window.
        var anchors = ResolvePlayerAnchors();
        if (anchors.MainHero == null && anchors.MainParty == null && anchors.MainPartyBase == null)
        {
            DiagOnce("no-anchors|" + typeName,
                () => $"scope: anchors unresolved while classifying {typeName} -- failing open");
            return true;
        }

        if (string.Equals(scope, "Party only", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(scope, "Party", StringComparison.OrdinalIgnoreCase))
        {
            // Match if any referenced hero IS the main hero OR is in the
            // player's party (PartyBelongedTo == MainParty). Match parties
            // against MobileParty AND PartyBase forms because LogEntry
            // subclasses use both interchangeably.
            if (anchors.MainHero != null && refs.Heroes.Contains(anchors.MainHero)) return true;
            if (anchors.MainParty != null && refs.Parties.Contains(anchors.MainParty)) return true;
            if (anchors.MainPartyBase != null && refs.Parties.Contains(anchors.MainPartyBase)) return true;
            // Check by reference-equality across the party set: entries can
            // hold either MobileParty.Party (PartyBase) or the MobileParty
            // itself; refs.Parties is heterogeneous.
            foreach (var p in refs.Parties)
            {
                if (anchors.MainParty != null && ReferenceEquals(p, anchors.MainParty)) return true;
                if (anchors.MainPartyBase != null && ReferenceEquals(p, anchors.MainPartyBase)) return true;
                // Cross-check: if p is a MobileParty, compare its .Party to MainPartyBase
                var pParty = GetMember(p, "Party");
                if (pParty != null && anchors.MainPartyBase != null && ReferenceEquals(pParty, anchors.MainPartyBase)) return true;
                // Cross-check: if p is a PartyBase, compare its .MobileParty to MainParty
                var pMobile = GetMember(p, "MobileParty");
                if (pMobile != null && anchors.MainParty != null && ReferenceEquals(pMobile, anchors.MainParty)) return true;
            }
            // Hero-by-party: any hero in refs whose PartyBelongedTo IS the main party.
            foreach (var h in refs.Heroes)
            {
                var hParty = GetMember(h, "PartyBelongedTo");
                if (hParty != null && anchors.MainParty != null && ReferenceEquals(hParty, anchors.MainParty)) return true;
            }
            return false;
        }
        if (string.Equals(scope, "Clan only", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(scope, "Clan", StringComparison.OrdinalIgnoreCase))
        {
            if (anchors.PlayerClan == null) return true;
            if (refs.Clans.Contains(anchors.PlayerClan)) return true;
            // Match heroes' clans
            foreach (var h in refs.Heroes)
            {
                var hClan = GetMember(h, "Clan");
                if (hClan != null && ReferenceEquals(hClan, anchors.PlayerClan)) return true;
            }
            // Match parties' owner clans (handle both MobileParty and PartyBase forms)
            foreach (var p in refs.Parties)
            {
                var leader = GetMember(p, "LeaderHero") ?? GetMember(p, "Leader");
                if (leader == null)
                {
                    // PartyBase exposes the underlying MobileParty; try one indirection
                    var mp = GetMember(p, "MobileParty");
                    if (mp != null) leader = GetMember(mp, "LeaderHero") ?? GetMember(mp, "Leader");
                }
                var leaderClan = leader != null ? GetMember(leader, "Clan") : null;
                if (leaderClan != null && ReferenceEquals(leaderClan, anchors.PlayerClan)) return true;
            }
            return false;
        }
        if (string.Equals(scope, "Kingdom only", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(scope, "Kingdom", StringComparison.OrdinalIgnoreCase))
        {
            if (anchors.PlayerKingdom == null) return true;
            if (refs.Kingdoms.Contains(anchors.PlayerKingdom)) return true;
            foreach (var h in refs.Heroes)
            {
                var hClan = GetMember(h, "Clan");
                var hKingdom = hClan != null ? GetMember(hClan, "Kingdom") : null;
                if (hKingdom != null && ReferenceEquals(hKingdom, anchors.PlayerKingdom)) return true;
            }
            foreach (var c in refs.Clans)
            {
                var cKingdom = GetMember(c, "Kingdom");
                if (cKingdom != null && ReferenceEquals(cKingdom, anchors.PlayerKingdom)) return true;
            }
            return false;
        }

        // Unknown scope value: fail open (don't filter).
        return true;
    }

    /// <summary>
    /// Walks the LogEntry's relevant entity-typed properties/fields, classifying
    /// each non-null value into Heroes / Parties / Clans / Kingdoms.
    ///
    /// Phase W.25 perf: at type-discovery time we filter the member list down
    /// to only those whose declared type's name (or any base in its chain)
    /// matches one of {Hero, MobileParty, PartyBase, Clan, Kingdom, Settlement}.
    /// Skipping string/int/enum/TextObject properties cuts the per-LogEntry
    /// reflection work by ~80% and was the main source of lag at scope=
    /// Party/Clan/Kingdom (the only paths that call this).
    /// </summary>
    private static EntityRefs ExtractEntityRefs(object logEntry)
    {
        var refs = new EntityRefs();
        try
        {
            var t = logEntry.GetType();
            if (!_relevantPropsCache.TryGetValue(t, out var props))
            {
                var raw = t.GetProperties(BindingFlags.Public | BindingFlags.Instance);
                var list = new List<PropertyInfo>(raw.Length);
                foreach (var p in raw)
                {
                    if (p.GetIndexParameters().Length > 0) continue;
                    if (IsRelevantEntityType(p.PropertyType)) list.Add(p);
                }
                props = list.ToArray();
                _relevantPropsCache[t] = props;
            }
            foreach (var p in props)
            {
                object? v;
                try { v = p.GetValue(logEntry); } catch { continue; }
                if (v == null) continue;
                ClassifyValue(v, refs);
            }

            if (!_relevantFieldsCache.TryGetValue(t, out var fields))
            {
                var raw = t.GetFields(BindingFlags.Public | BindingFlags.Instance);
                var list = new List<FieldInfo>(raw.Length);
                foreach (var f in raw)
                {
                    if (IsRelevantEntityType(f.FieldType)) list.Add(f);
                }
                fields = list.ToArray();
                _relevantFieldsCache[t] = fields;
            }
            foreach (var f in fields)
            {
                object? v;
                try { v = f.GetValue(logEntry); } catch { continue; }
                if (v == null) continue;
                ClassifyValue(v, refs);
            }
        }
        catch { }
        return refs;
    }

    // Returns true when the declared type IS or could be a Hero / MobileParty /
    // PartyBase / Clan / Kingdom / Settlement (or a derived class). Indexed by
    // Type to avoid walking the inheritance chain on every call. The type's
    // full inheritance chain is checked once on first encounter.
    private static readonly Dictionary<Type, bool> _isRelevantEntityTypeCache = new();
    private static bool IsRelevantEntityType(Type t)
    {
        if (_isRelevantEntityTypeCache.TryGetValue(t, out var cached)) return cached;
        // Skip primitives, enums, and obviously-irrelevant types. Object and
        // interfaces both could in theory carry an entity, so we don't bail
        // out on those -- they'll just walk the loop below.
        bool result = false;
        if (!t.IsPrimitive && !t.IsEnum && t != typeof(string))
        {
            var cur = t;
            while (cur != null && cur != typeof(object))
            {
                var n = cur.Name;
                if (n == "Hero" || n == "MobileParty" || n == "PartyBase" ||
                    n == "Clan" || n == "Kingdom" || n == "Settlement")
                {
                    result = true;
                    break;
                }
                cur = cur.BaseType;
            }
        }
        _isRelevantEntityTypeCache[t] = result;
        return result;
    }

    private static void ClassifyValue(object v, EntityRefs refs)
    {
        // Walk inheritance: many subclasses inherit from Hero / Clan etc.
        // Match by simple name OR by walking up base types.
        if (IsTypeOrSubclass(v.GetType(), "Hero"))                   refs.Heroes.Add(v);
        else if (IsTypeOrSubclass(v.GetType(), "MobileParty"))       refs.Parties.Add(v);
        else if (IsTypeOrSubclass(v.GetType(), "PartyBase"))         refs.Parties.Add(v);
        else if (IsTypeOrSubclass(v.GetType(), "Clan"))              refs.Clans.Add(v);
        else if (IsTypeOrSubclass(v.GetType(), "Kingdom"))           refs.Kingdoms.Add(v);
        else if (IsTypeOrSubclass(v.GetType(), "Settlement"))
        {
            // A settlement isn't directly a clan, but its OwnerClan often
            // determines relevance. Resolve and add.
            var owner = GetMember(v, "OwnerClan");
            if (owner != null) refs.Clans.Add(owner);
        }
    }

    private static bool IsTypeOrSubclass(Type t, string simpleName)
    {
        var cur = t;
        while (cur != null && cur != typeof(object))
        {
            if (cur.Name == simpleName) return true;
            cur = cur.BaseType;
        }
        return false;
    }

    private static object? GetMember(object obj, string name)
    {
        if (obj == null) return null;
        try
        {
            var t = obj.GetType();
            var p = t.GetProperty(name, BindingFlags.Public | BindingFlags.Instance);
            if (p != null && p.GetIndexParameters().Length == 0) return p.GetValue(obj);
            var f = t.GetField(name, BindingFlags.Public | BindingFlags.Instance);
            return f?.GetValue(obj);
        }
        catch { return null; }
    }

    private struct PlayerAnchors
    {
        public object? MainHero;
        public object? MainParty;       // MobileParty
        public object? MainPartyBase;   // PartyBase (MobileParty.Party)
        public object? PlayerClan;
        public object? PlayerKingdom;
    }

    // Phase W.25: cache anchors with the same lock-free pattern as
    // CrestMessageStyle.RefreshPlayerAnchors. Every LogEntry was triggering
    // 4 TypeByName + 5 GetProperty/GetValue + 2 GetMember calls --
    // significant in heavy world-map ticks. Cache for 5 seconds; refreshed
    // by Interlocked-claimed slot.
    private static PropertyInfo? _heroMainHeroProp;
    private static PropertyInfo? _partyMainPartyProp;
    private static PropertyInfo? _clanPlayerClanProp;
    private static bool _staticPropsResolved;
    private static PlayerAnchors _cachedAnchors;
    private static long _anchorCacheAtTicks;
    private static int _anchorCacheRefreshing;
    private static readonly long AnchorCacheFreshTicks = TimeSpan.TicksPerSecond * 5;

    private static PlayerAnchors ResolvePlayerAnchors()
    {
        var now = DateTime.UtcNow.Ticks;
        var resolved = System.Threading.Volatile.Read(ref _anchorCacheAtTicks);
        if (resolved != 0 && now - resolved < AnchorCacheFreshTicks) return _cachedAnchors;

        if (System.Threading.Interlocked.CompareExchange(ref _anchorCacheRefreshing, 1, 0) != 0) return _cachedAnchors;
        try
        {
            if (!_staticPropsResolved)
            {
                _staticPropsResolved = true;
                try
                {
                    var heroType  = AccessTools2.TypeByName("TaleWorlds.CampaignSystem.Hero");
                    var partyType = AccessTools2.TypeByName("TaleWorlds.CampaignSystem.Party.MobileParty");
                    var clanType  = AccessTools2.TypeByName("TaleWorlds.CampaignSystem.Clan");
                    _heroMainHeroProp   = heroType?.GetProperty("MainHero",   BindingFlags.Public | BindingFlags.Static);
                    _partyMainPartyProp = partyType?.GetProperty("MainParty", BindingFlags.Public | BindingFlags.Static);
                    _clanPlayerClanProp = clanType?.GetProperty("PlayerClan", BindingFlags.Public | BindingFlags.Static);
                }
                catch { }
            }

            var a = new PlayerAnchors();
            try
            {
                a.MainHero      = _heroMainHeroProp?.GetValue(null);
                a.MainParty     = _partyMainPartyProp?.GetValue(null);
                a.MainPartyBase = a.MainParty != null ? GetMember(a.MainParty, "Party") : null;
                a.PlayerClan    = _clanPlayerClanProp?.GetValue(null);
                a.PlayerKingdom = a.PlayerClan != null ? GetMember(a.PlayerClan, "Kingdom") : null;
            }
            catch { }
            _cachedAnchors = a;
            System.Threading.Volatile.Write(ref _anchorCacheAtTicks, now);
            return a;
        }
        finally
        {
            System.Threading.Interlocked.Exchange(ref _anchorCacheRefreshing, 0);
        }
    }

    private static readonly Dictionary<Type, PropertyInfo[]> _relevantPropsCache  = new();
    private static readonly Dictionary<Type, FieldInfo[]>    _relevantFieldsCache = new();

    private sealed class EntityRefs
    {
        public readonly HashSet<object> Heroes   = new();
        public readonly HashSet<object> Parties  = new();
        public readonly HashSet<object> Clans    = new();
        public readonly HashSet<object> Kingdoms = new();
        public bool IsEmpty => Heroes.Count == 0 && Parties.Count == 0 && Clans.Count == 0 && Kingdoms.Count == 0;
    }
}
