using MCM.Abstractions;
using MCM.Abstractions.Attributes;
using MCM.Abstractions.Attributes.v2;
using MCM.Abstractions.Base.Global;
using MCM.Common;

using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace MCM.UI
{
    /// <summary>
    /// CREST Phase L: in-game MCM checkboxes for the runtime gating flags
    /// declared in <c>Modules\CREST\crest.json</c> and consumed by
    /// <c>Bannerlord.Harmony.CrestConfig</c>.
    ///
    /// Two-way sync model:
    ///   * crest.json is the source of truth for early-startup gates (it's read
    ///     during OnSubModuleLoad, before MCM has finished loading its own
    ///     storage).
    ///   * MCM stores its own copy at Configs\ModSettings\Global\MCM\CREST_v1.json
    ///     so the checkboxes have somewhere to persist between game sessions.
    ///   * On LOADING_COMPLETE we overwrite the loaded properties from
    ///     crest.json so manual edits to that file (or values written by another
    ///     session) propagate forward.
    ///   * On SAVE_TRIGGERED we write property values back to crest.json so the
    ///     gates pick them up on the next launch.
    ///
    /// Phase W.4 ordering convention: every property carries an explicit
    /// <c>Order = N</c> and every group an explicit <c>GroupOrder = N</c>.
    /// MCM v5's UI sorts by <c>Order</c> ASC, then by alphanumeric DisplayName
    /// (see <c>UISettingsUtils.SettingsPropertyVMComparer</c>). With Order set,
    /// we guarantee deterministic top-to-bottom display matching declaration
    /// intent rather than alphabetic surprise.
    /// </summary>
    internal sealed class CrestSettings : AttributeGlobalSettings<CrestSettings>
    {
        // Phase W.16: register the per-property visibility hook so the
        // campaign-log bucket toggles disappear when LogFilterScope is set
        // to anything other than "None" (where they have no effect anyway).
        // Static so it fires regardless of whether the user opens the
        // settings page before or after the hook is registered.
        static CrestSettings()
        {
            try
            {
                global::MCM.UI.GUI.ViewModels.SettingsPropertyVM.IsPropertyVisibleHook =
                    (displayName, owner) =>
                    {
                        if (!(owner is CrestSettings crest)) return true;
                        // Campaign-log filter buckets: visible only at scope=None.
                        if (displayName.IndexOf("CrestSettings_Filter", StringComparison.Ordinal) >= 0)
                        {
                            var scope = crest.LogFilterScope?.SelectedValue ?? "None";
                            return string.Equals(scope, "None", StringComparison.OrdinalIgnoreCase);
                        }
                        return true;
                    };
            }
            catch { /* best-effort */ }
        }


        // Phase W.22: DisplayName uses leading space to sort CREST to the top
        // of MCM's module list (whitespace sorts before letters in most
        // collations). The space is intentional and required for sort ordering.
        public override string Id => "CREST_v1";
        public override string DisplayName => " CREST";
        public override string FolderName => "MCM";
        public override string FormatType => "json2";

        // Phase W.18: subscribe to the scope dropdown's PropertyChanged event
        // so we can trigger an MCM UI visibility refresh as soon as the user
        // picks a new value. Without this, IsPropertyVisibleHook wouldn't
        // re-evaluate until the user closed and reopened the settings page.
        //
        // Phase W.22: also write through to crest.json on every change.
        // MCM's SaveTriggered lifecycle event doesn't fire reliably for
        // dropdown changes (only when the user clicks Save or exits the
        // page), so the patch's runtime read of crest.json could lag
        // behind what the user just selected. Writing on every change
        // keeps the two storage locations in sync end-to-end.
        public CrestSettings()
        {
            try
            {
                if (LogFilterScope is INotifyPropertyChanged inpc)
                {
                    inpc.PropertyChanged += (sender, args) =>
                    {
                        // Dropdown<T> fires PropertyChanged for SelectedIndex and
                        // SelectedValue. Refresh visibility AND persist to disk.
                        global::MCM.UI.GUI.ViewModels.ModOptionsVM.RefreshVisibility();
                        try { WriteToCrestJson(); } catch { /* best-effort */ }
                    };
                }
            }
            catch { /* best-effort */ }
        }

        // Y.22c: field defaults are the "Vanilla Plus" baseline. New users
        // get a curated, opinionated CREST experience out of the box (since
        // they almost certainly downloaded the bundle for the QoL features).
        // Anyone who wants stock Bannerlord behavior can pick the Default
        // preset from the upper-left dropdown. Anyone who wants a different
        // mix can edit individual toggles -- the Custom preset will track
        // their changes automatically.
        private bool _butterLib = true;
        private bool _mcm = true;
        private bool _mcmBasicImplementation = true;
        private bool _mcmUI = true;
        private bool _skipIntroVideo = true;
        // Y.22c: replaces the MainMenuMonotone MCM toggle. The runtime
        // monotone-color behavior is still applied (it's gated by the
        // "MainMenuMonotone" key in crest.json which CrestConfig defaults
        // to true). What this toggle controls is the message-suppression
        // layer (CrestMessageStyle reads "SuppressMainMenuMessages") so
        // the cluster of mod-load announcements doesn't crowd the menu.
        private bool _suppressMainMenuMessages = true;
        // Y.22 follow-up: master toggle that hides the CREST Sub-modules group's
        // sub-options (ButterLib / MCM / MCM-Basic / MCM-UI). Default OFF so
        // the advanced toggles never surprise a casual user.
        private bool _showAdvancedSettings = false;

        // Phase W.4 master toggle: gates the entire campaign log filter group.
        // Y.22c: default ON because the campaign log gets very noisy mid/late
        // game; the scope dropdown's default ("Party only", set in the field
        // initializer below) is the conservative, recommended setting.
        private bool _enableLogFiltering = true;

        // Phase W: Campaign log filter buckets. Default true = pass through
        // (no filtering). Sub-settings only take effect when EnableLogFiltering
        // is on (the whole group hides when master is off).
        private bool _filterSkillLogs        = true;
        private bool _filterHeroEvents       = true;
        private bool _filterRelationLogs     = true;
        private bool _filterKingdomLogs      = true;
        private bool _filterMinorBattleLogs  = true;
        private bool _filterQuestLogs        = true;

        // Phase Y.1 / Y.5: Time controls. v1.4.2 InputKey enum has
        // a non-obvious layout (verified by runtime dump):
        //   D0=11  D1=2  D2=3  D3=4  D4=5  D5=6  D6=7  D7=8  D8=9  D9=10
        // The user-facing 0-9 in MCM is mapped through DigitToInputKeyCode
        // / InputKeyCodeToDigit so the displayed number always matches what
        // a player's keyboard actually sends.
        // Y.22c: master ON for Vanilla Plus baseline.
        private bool  _enableFasterTime           = true;
        private float _fasterTimeUltraFastSpeed   = 16f;
        private float _fasterTimeSuperFastSpeed   = 5f;
        private int   _fasterTimeUltraFastHotkey  = 6;  // InputKey.D5
        private int   _fasterTimeSuperFastHotkey  = 5;  // InputKey.D4

        // Phase Y.2: Cut-through swings. Master OFF by default (a meaningful
        // jump in combat lethality; opt-in only). Sub-toggles default to
        // reasonable behavior so on a fresh enable the behavior matches
        // typical usage.
        private bool  _enableCutThroughEveryone        = false;
        private bool  _cutThroughAlsoForAI             = false;
        private bool  _cutThroughFriendliesBlock       = true;
        private bool  _cutThroughOnlyKilledUnits       = false;
        private float _cutThroughDamageRetainedPerCut  = 0.8f;
        private float _cutThroughArmorThreshold        = 0.5f;

        // Phase Y.3 / Y.13 unified tactical: hotkey defaults to numpad *
        // (InputKey.Multiply = 55). Time-slow factor 15% real-time.
        // Y.22c: master ON for Vanilla Plus baseline.
        private bool  _enableCompanionHotswap          = true;
        // Y.12d-fix22: default hotkey is Z (InputKey.Z = 44). Old default was
        // NumpadMultiply (55) which collided with RTSCamera's slow-down-time
        // binding. Z is right under A â€” easy left-hand reach, no vanilla bind.
        private int   _companionHotswapHotkeyLeft      = 36;   // InputKey.J (Z conflicts with vanilla crouch)
        private int   _companionHotswapHotkeyRight     = 36;
        private float _companionHotswapTimeSlowFactor  = 0.15f;

        // Phase Y.5/Y.5b: Campaign Tweaks. Curated small Harmony-patch QoL
        // toggles.
        // Y.22c: master ON; the no-brainer QoL picks (NoArrowsStuck,
        // LootCapturedHeroes, LifelongLearning, AchievementsWithMods) are
        // ON. Anything that meaningfully changes campaign economy or
        // pace stays OFF.
        private bool  _enableCampaignTweaks             = true;
        private bool  _preventClanDeath                 = false;
        private bool  _preventClanDeathPlayerOnly       = false;
        private bool  _playerNoFlinch                   = false;
        private bool  _noExecutionPenalty               = false;
        private bool  _clanTournamentExclusion          = false;
        private float _clanPartySpeedBonus              = 0f;
        // Y.5b additions:
        private bool  _stopPrisonerEscape               = false;
        private bool  _lootCapturedHeroes               = true;
        private bool  _enablePlayerHealthRegen          = false;
        private float _playerHealthRegenPerSec          = 1f;
        private bool  _noArrowsStuck                    = true;
        private bool  _marriageStaysInClan              = false;
        private bool  _pregnancyChanceUncapped          = false;
        private float _pregnancyMinChance               = 0.05f;
        private bool  _unlockAllSmithingRecipes         = false;
        // Phase Y.19 / Y.20:
        private bool  _lifelongLearning                 = true;
        private float _lifelongLearningMinRate          = 0.5f;
        private bool  _enableAchievementsWithMods       = true;
        private int   _tavernCompanionMultiplier        = 1;
        // Phase Y.23: Faster Ships. NavalDLC ship parties travel painfully
        // slowly on the campaign map; 2x is a quality-of-life sweet spot
        // (still slower than land cavalry, faster than walking). Vanilla
        // Plus default is ON at 2.0x.
        private bool  _enableFasterShips                = true;
        private float _fasterShipsMultiplier            = 2.0f;
        // Phase Y.12: Reinforcement system. Off by default (changes battle
        // pacing meaningfully); when on, default values give roughly 1.5x
        // wave size at vanilla intervals and cap. Vanilla Plus enables this
        // at 1.5x because bigger battles feel better with the QoL preset.
        private bool  _enableReinforcements             = true;
        private float _reinforcementWaveMultiplier      = 1.5f;
        private float _reinforcementIntervalSec         = -1f;   // -1 sentinel = leave vanilla (~30s)
        private int   _reinforcementMaxWaves            = -1;    // -1 sentinel = leave vanilla (8)
        // Phase Y.12b: Battle Convergence. Nearby AI parties join your battle
        // when the encounter starts. On in Vanilla Plus at modest defaults
        // (25 campaign-units radius, 3 joiners per side cap) -- big battles
        // become possible without the small-skirmish baseline being affected.
        private bool  _enableBattleConvergence          = true;
        // Y.12b-fix: bumped default from 25 to 75. 25 was too tight --
        // typical "visible on screen near the player" lords are 30-100
        // campaign-map units away, so 25 only caught parties practically
        // on top of the player. 75 covers a comfortable on-screen radius.
        private float _battleConvergenceRadius          = 75f;
        private int   _battleConvergenceMaxJoinersPerSide = 3;
        // Y.12d-fix18: progressive vs slider, EITHER-OR.
        // Default ON: radius scales with clan tier (grows with renown).
        // Default OFF: radius = the slider value above (flat).
        // Y.12d-fix19: simplified the multiplier to a small integer "range boost"
        // (x1/x2/x3) that's intuitive for players. The actual per-tier base is
        // now a fixed engine constant (BASE_PER_TIER in CrestBattleConvergence).
        private bool  _battleConvergenceClanTierScaling = true;
        private int   _battleConvergenceClanTierMultiplier = 1;  // x1 default, max x3
        // Y.12d-fix26 (Cinema preset): bigger battlefield knobs, no MCM UI yet
        // â€” preset and JSON round-trip only. EnableBattleConvergence stays the
        // master switch; these are the dial-to-11 tuning constants used by the
        // Cinema preset and (optionally) by power users editing crest.json.
        private bool  _battleConvergenceDisableFilters    = false;
        private int   _battleConvergenceMaxActiveJoiners  = 5;
        private int   _battleConvergenceInitialDelaySec   = 45;
        private int   _battleConvergenceCadenceSec        = 5;
        private bool  _enablePlayerInvincible             = false;

        // Y.29: Cinema Tools master toggle. Gates the Item/Troop spawner
        // buttons in MCM. Default OFF; ON in Cinema preset.
        private bool  _enableCinemaTools                  = false;
        // (Y.11 battle-size adjuster: no MCM controls -- managed entirely
        //  via the in-game Options menu now.)

        // Phase Y.7: Troop tier unlocker.
        // Y.22c: master ON for Vanilla Plus baseline. Vanilla cap is 6;
        // modded troops typically max at 7 or 8. Cap 7 is the safe pick.
        private bool _enableTierUnlocker                = true;
        private int  _tierUnlockerMax                   = 7;
        private int  _tierUnlockerVolunteerMax          = 7;

        // v1.4.2 InputKey codes for the digit row.
        // ---------------------------------------------------------------
        // Y.29 Cinema Tools helpers. Reflection-based so they degrade
        // gracefully across TaleWorlds versions instead of throwing
        // MissingMethodException at runtime.
        // ---------------------------------------------------------------
        private static void CrestSettings_CinemaTools_TrySetCheatMode(bool enable)
        {
            try
            {
                var gameType = Type.GetType("TaleWorlds.Core.Game, TaleWorlds.Core");
                if (gameType == null) gameType = AppDomain.CurrentDomain.GetAssemblies()
                    .Select(a => a.GetType("TaleWorlds.Core.Game"))
                    .FirstOrDefault(t => t != null);
                if (gameType == null) return;
                var current = gameType.GetProperty("Current",
                    System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static)?.GetValue(null);
                if (current == null) return;
                var cheatProp = gameType.GetProperty("CheatMode",
                    System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance);
                if (cheatProp == null) return;
                cheatProp.SetValue(current, enable);
            }
            catch { /* best-effort */ }
        }

        private static void CrestSettings_CinemaTools_TryOpenItemSpawner()
        {
            CrestSettings_CinemaTools_TrySetCheatMode(true);
            try
            {
                // InventoryManager.OpenScreenAsInventory() opens the player's
                // inventory in cheat mode, exposing all items.
                var invMgr = AppDomain.CurrentDomain.GetAssemblies()
                    .Select(a => a.GetType("TaleWorlds.CampaignSystem.Inventory.InventoryManager"))
                    .FirstOrDefault(t => t != null);
                if (invMgr == null) {
                    invMgr = AppDomain.CurrentDomain.GetAssemblies()
                        .Select(a => a.GetType("TaleWorlds.CampaignSystem.InventoryManager"))
                        .FirstOrDefault(t => t != null);
                }
                if (invMgr == null) {
                    TryDisplayMessage("Cheat mode enabled. Open your Inventory manually."); return;
                }
                var openMethod = invMgr.GetMethod("OpenScreenAsInventory",
                    System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static,
                    null, Type.EmptyTypes, null);
                if (openMethod != null) { openMethod.Invoke(null, null); }
                else { TryDisplayMessage("Cheat mode enabled. Open your Inventory manually."); }
            }
            catch { TryDisplayMessage("Cheat mode enabled. Open your Inventory manually."); }
        }

        private static void CrestSettings_CinemaTools_TryOpenTroopSpawner()
        {
            CrestSettings_CinemaTools_TrySetCheatMode(true);
            try
            {
                var psmType = AppDomain.CurrentDomain.GetAssemblies()
                    .Select(a => a.GetType("TaleWorlds.CampaignSystem.Party.PartyScreenManager"))
                    .FirstOrDefault(t => t != null);
                if (psmType == null) {
                    psmType = AppDomain.CurrentDomain.GetAssemblies()
                        .Select(a => a.GetType("TaleWorlds.CampaignSystem.PartyScreenManager"))
                        .FirstOrDefault(t => t != null);
                }
                if (psmType == null) {
                    TryDisplayMessage("Cheat mode enabled. Open your Party manually."); return;
                }
                // Try OpenScreenAsPartyManagement(MobileParty) first (has access to cheat troop pool)
                var mpType = AppDomain.CurrentDomain.GetAssemblies()
                    .Select(a => a.GetType("TaleWorlds.CampaignSystem.Party.MobileParty"))
                    .FirstOrDefault(t => t != null);
                if (mpType == null) mpType = AppDomain.CurrentDomain.GetAssemblies()
                    .Select(a => a.GetType("TaleWorlds.CampaignSystem.MobileParty"))
                    .FirstOrDefault(t => t != null);
                object? mainParty = null;
                try { mainParty = mpType?.GetProperty("MainParty",
                    System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static)?.GetValue(null); } catch { }
                var candidates = new[] { "OpenScreenAsPartyManagement", "OpenScreenAsManageTroops", "OpenScreenAsManageTroopsLogic" };
                System.Reflection.MethodInfo? opened = null;
                foreach (var n in candidates) {
                    opened = psmType.GetMethod(n,
                        System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static,
                        null, mainParty != null ? new[] { mpType! } : Type.EmptyTypes, null);
                    if (opened != null) break;
                }
                if (opened != null) {
                    try { opened.Invoke(null, opened.GetParameters().Length == 0 ? null : new object?[] { mainParty }); }
                    catch { TryDisplayMessage("Cheat mode enabled. Open your Party manually."); }
                } else {
                    TryDisplayMessage("Cheat mode enabled. Open your Party manually.");
                }
            }
            catch { TryDisplayMessage("Cheat mode enabled. Open your Party manually."); }
        }

        private static void TryDisplayMessage(string text)
        {
            try { TaleWorlds.Library.InformationManager.DisplayMessage(new TaleWorlds.Library.InformationMessage(text, TaleWorlds.Library.Color.FromUint(0xFFFFAA22))); } catch { }
        }

        private static int DigitToInputKeyCode(int digit)
        {
            if (digit == 0) return 11;       // D0
            if (digit >= 1 && digit <= 9) return digit + 1;  // D1..D9 = 2..10
            return 6;                         // bogus -> D5 fallback
        }
        private static int InputKeyCodeToDigit(int code)
        {
            if (code == 11) return 0;        // D0
            if (code >= 2 && code <= 10) return code - 1;  // D1..D9
            return -1;                        // unknown -> "?" in MCM
        }

        // ---------------------------------------------------------------
        // Group 1: Quality of Life (GroupOrder = 1)
        // ---------------------------------------------------------------
        [SettingPropertyBool("{=CrestSettings_SkipIntro}Skip TaleWorlds intro video", Order = 1, RequireRestart = true,
            HintText = "{=CrestSettings_SkipIntroDesc}Disable the TaleWorlds startup logo video for faster game launch. Restart required.")]
        [SettingPropertyGroup("{=CrestSettings_GroupQol}Quality of Life", GroupOrder = 1)]
        public bool SkipIntroVideo { get => _skipIntroVideo; set { if (_skipIntroVideo != value) { _skipIntroVideo = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_SuppressMainMenuMessages}Hide main-menu mod messages", Order = 2, RequireRestart = true,
            HintText = "{=CrestSettings_SuppressMainMenuMessagesDesc}Hide the cluster of mod-load announcements that mods spam onto the main-menu message stack at startup. The messages are still mirrored to Modules\\CREST\\main-menu-messages.log if you want to read them. Suppression releases automatically once you start a campaign / custom battle / load a save -- gameplay messages display normally. Restart required.")]
        [SettingPropertyGroup("{=CrestSettings_GroupQol}Quality of Life", GroupOrder = 1)]
        public bool SuppressMainMenuMessages { get => _suppressMainMenuMessages; set { if (_suppressMainMenuMessages != value) { _suppressMainMenuMessages = value; OnPropertyChanged(); } } }

        // ---------------------------------------------------------------
        // Group 2: Campaign Log Filter (GroupOrder = 2)
        // ---------------------------------------------------------------
        // Master toggle MUST live in this group (not QoL) so MCM uses it as
        // THIS group's IsToggle and not as QoL's. Order=0 places it on top.
        [SettingPropertyBool("{=CrestSettings_EnableLogFilter}Enable campaign log filtering", Order = 0, IsToggle = true, RequireRestart = false,
            HintText = "{=CrestSettings_EnableLogFilterDesc}Master switch for the campaign log filter. When OFF, every campaign-log entry passes through normally and the filter sub-options are hidden. When ON, the scope dropdown and per-category checkboxes apply. Takes effect immediately - no restart required.")]
        [SettingPropertyGroup("{=CrestSettings_GroupLogFilter}Campaign Log Filter", GroupOrder = 2)]
        public bool EnableLogFiltering { get => _enableLogFiltering; set { if (_enableLogFiltering != value) { _enableLogFiltering = value; OnPropertyChanged(); } } }

        // Phase W.3: scope dropdown -- applies before per-category gating.
        // Listed first (Order=2 inside the group, after the master toggle)
        // so the user sees the broad lever before the fine-grained category toggles.
        [SettingPropertyDropdown("{=CrestSettings_LogFilterScope}Scope: who do you want to hear about?", Order = 2, RequireRestart = false,
            HintText = "{=CrestSettings_LogFilterScopeDesc}Coarse-grained relevance filter. None = per-category toggles apply (you control which categories are muted). All = hide every classified chatter message. Party only = keep only messages mentioning your hero or main party. Clan only = keep only messages mentioning your hero/party/clan. Kingdom only = keep only messages mentioning your hero/party/clan/kingdom. The category toggles below only matter at scope=None and are hidden at other scopes.")]
        [SettingPropertyGroup("{=CrestSettings_GroupLogFilter}Campaign Log Filter", GroupOrder = 2)]
        // Y.22c: default index 2 = "Party only" (the conservative recommended
        // default â€” mid/late game vanilla campaign log gets very noisy with
        // chatter about NPCs the player has never met). Users who want
        // unfiltered output can flip to "None"; users who want maximum signal
        // can flip to "Clan only" / "Kingdom only".
        public Dropdown<string> LogFilterScope { get; set; } = new(new[]
        {
            "None",
            "All",
            "Party only",
            "Clan only",
            "Kingdom only",
        }, 2);

        [SettingPropertyBool("{=CrestSettings_FilterSkill}Skill / level-up notifications", Order = 3, RequireRestart = false,
            HintText = "{=CrestSettings_FilterSkillDesc}When ON: 'Hero X has gained the Athletics skill', 'Hero Y reached level 10', perk-selection announcements all show normally. Turn OFF to suppress these in the campaign log. Only takes effect at Scope = None.")]
        [SettingPropertyGroup("{=CrestSettings_GroupLogFilter}Campaign Log Filter", GroupOrder = 2)]
        public bool FilterSkillLogs { get => _filterSkillLogs; set { if (_filterSkillLogs != value) { _filterSkillLogs = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_FilterHero}Hero life events", Order = 4, RequireRestart = false,
            HintText = "{=CrestSettings_FilterHeroDesc}Hero births, deaths, marriages, came-of-age. ON shows them; OFF mutes the entire category. Only takes effect at Scope = None.")]
        [SettingPropertyGroup("{=CrestSettings_GroupLogFilter}Campaign Log Filter", GroupOrder = 2)]
        public bool FilterHeroEvents { get => _filterHeroEvents; set { if (_filterHeroEvents != value) { _filterHeroEvents = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_FilterRelation}Relation changes", Order = 5, RequireRestart = false,
            HintText = "{=CrestSettings_FilterRelationDesc}'Hero X likes you more / less'. ON shows them; OFF mutes the entire category. Only takes effect at Scope = None.")]
        [SettingPropertyGroup("{=CrestSettings_GroupLogFilter}Campaign Log Filter", GroupOrder = 2)]
        public bool FilterRelationLogs { get => _filterRelationLogs; set { if (_filterRelationLogs != value) { _filterRelationLogs = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_FilterKingdom}Kingdom politics (war / peace / decisions)", Order = 6, RequireRestart = false,
            HintText = "{=CrestSettings_FilterKingdomDesc}Wars declared, peace made, kingdom decisions, clan changes-of-allegiance, policy votes. ON shows them; OFF mutes the entire category. Only takes effect at Scope = None.")]
        [SettingPropertyGroup("{=CrestSettings_GroupLogFilter}Campaign Log Filter", GroupOrder = 2)]
        public bool FilterKingdomLogs { get => _filterKingdomLogs; set { if (_filterKingdomLogs != value) { _filterKingdomLogs = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_FilterMinorBattle}Minor world events (raids / prisoners / defenses)", Order = 7, RequireRestart = false,
            HintText = "{=CrestSettings_FilterMinorBattleDesc}World-map chatter NPCs generate around you: looter / bandit / minor-encounter outcomes, '<X> is raided by <Y>', '<X> has been taken prisoner by <Y>', '<X> has been released after battle', NPC parties defending settlements. ON shows them; OFF mutes the entire category. Only takes effect at Scope = None.")]
        [SettingPropertyGroup("{=CrestSettings_GroupLogFilter}Campaign Log Filter", GroupOrder = 2)]
        public bool FilterMinorBattleLogs { get => _filterMinorBattleLogs; set { if (_filterMinorBattleLogs != value) { _filterMinorBattleLogs = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_FilterQuest}Quest / issue / tournament notifications", Order = 8, RequireRestart = false,
            HintText = "{=CrestSettings_FilterQuestDesc}Issues started / completed by the player, quest-finished announcements, tournament-started messages. ON shows them; OFF mutes the entire category. Only takes effect at Scope = None.")]
        [SettingPropertyGroup("{=CrestSettings_GroupLogFilter}Campaign Log Filter", GroupOrder = 2)]
        public bool FilterQuestLogs { get => _filterQuestLogs; set { if (_filterQuestLogs != value) { _filterQuestLogs = value; OnPropertyChanged(); } } }

        // ---------------------------------------------------------------
        // Group 3: Time Controls (GroupOrder = 3)
        // ---------------------------------------------------------------
        [SettingPropertyBool("{=CrestSettings_EnableFasterTime}Enable time controls", Order = 0, IsToggle = true, RequireRestart = false,
            HintText = "{=CrestSettings_EnableFasterTimeDesc}Master switch for world-map fast-forward. When ON, the configured hotkeys override the default world-map fast-forward speed (4x) with custom multipliers. When OFF, the game uses its built-in time controls only. Takes effect immediately - no restart required.")]
        [SettingPropertyGroup("{=CrestSettings_GroupFasterTime}Time Controls", GroupOrder = 3)]
        public bool EnableFasterTime { get => _enableFasterTime; set { if (_enableFasterTime != value) { _enableFasterTime = value; OnPropertyChanged(); } } }

        [SettingPropertyFloatingInteger("{=CrestSettings_FasterTimeUltraFastSpeed}Ultra Fast Speed", 1f, 64f, "0.0x", Order = 2, RequireRestart = false,
            HintText = "{=CrestSettings_FasterTimeUltraFastSpeedDesc}Multiplier applied when the Ultra Fast Hotkey is held. Game default for fast-forward is 4x; default here is 16x.")]
        [SettingPropertyGroup("{=CrestSettings_GroupFasterTime}Time Controls", GroupOrder = 3)]
        public float FasterTimeUltraFastSpeed { get => _fasterTimeUltraFastSpeed; set { if (Math.Abs(_fasterTimeUltraFastSpeed - value) > 0.001f) { _fasterTimeUltraFastSpeed = value; OnPropertyChanged(); } } }

        [SettingPropertyFloatingInteger("{=CrestSettings_FasterTimeSuperFastSpeed}Super Fast Speed", 1f, 32f, "0.0x", Order = 3, RequireRestart = false,
            HintText = "{=CrestSettings_FasterTimeSuperFastSpeedDesc}Multiplier applied when the Super Fast Hotkey is held. Game default for fast-forward is 4x; default here is 5x.")]
        [SettingPropertyGroup("{=CrestSettings_GroupFasterTime}Time Controls", GroupOrder = 3)]
        public float FasterTimeSuperFastSpeed { get => _fasterTimeSuperFastSpeed; set { if (Math.Abs(_fasterTimeSuperFastSpeed - value) > 0.001f) { _fasterTimeSuperFastSpeed = value; OnPropertyChanged(); } } }

        [SettingPropertyInteger("{=CrestSettings_FasterTimeUltraFastHotkey}Ultra Fast Hotkey (number row 0-9)", 0, 9, "Number key {0}", Order = 4, RequireRestart = false,
            HintText = "{=CrestSettings_FasterTimeUltraFastHotkeyDesc}Top-row number key (0-9) that triggers Ultra Fast speed when held. Default is 5.")]
        [SettingPropertyGroup("{=CrestSettings_GroupFasterTime}Time Controls", GroupOrder = 3)]
        public int FasterTimeUltraFastHotkey
        {
            get => InputKeyCodeToDigit(_fasterTimeUltraFastHotkey);
            set { var code = DigitToInputKeyCode(value); if (_fasterTimeUltraFastHotkey != code) { _fasterTimeUltraFastHotkey = code; OnPropertyChanged(); } }
        }

        [SettingPropertyInteger("{=CrestSettings_FasterTimeSuperFastHotkey}Super Fast Hotkey (number row 0-9)", 0, 9, "Number key {0}", Order = 5, RequireRestart = false,
            HintText = "{=CrestSettings_FasterTimeSuperFastHotkeyDesc}Top-row number key (0-9) that triggers Super Fast speed when held. Default is 4.")]
        [SettingPropertyGroup("{=CrestSettings_GroupFasterTime}Time Controls", GroupOrder = 3)]
        public int FasterTimeSuperFastHotkey
        {
            get => InputKeyCodeToDigit(_fasterTimeSuperFastHotkey);
            set { var code = DigitToInputKeyCode(value); if (_fasterTimeSuperFastHotkey != code) { _fasterTimeSuperFastHotkey = code; OnPropertyChanged(); } }
        }

        // ---------------------------------------------------------------
        // Group 4: Combat (GroupOrder = 4)
        // ---------------------------------------------------------------
        [SettingPropertyBool("{=CrestSettings_EnableCutThrough}Enable cut-through swings", Order = 0, IsToggle = true, RequireRestart = false,
            HintText = "{=CrestSettings_EnableCutThroughDesc}Master switch for cut-through swings. When ON, melee swings can carry through multiple targets at reduced momentum. Takes effect immediately - no restart required.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCutThrough}Combat", GroupOrder = 4)]
        public bool EnableCutThroughEveryone { get => _enableCutThroughEveryone; set { if (_enableCutThroughEveryone != value) { _enableCutThroughEveryone = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_CutThroughAI}AI also cuts through", Order = 2, RequireRestart = false,
            HintText = "{=CrestSettings_CutThroughAIDesc}When OFF (default), only the player gets cut-through. When ON, every AI agent's swings can also pass through multiple targets - notably increases battle lethality.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCutThrough}Combat", GroupOrder = 4)]
        public bool CutThroughAlsoForAI { get => _cutThroughAlsoForAI; set { if (_cutThroughAlsoForAI != value) { _cutThroughAlsoForAI = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_CutThroughFriendliesBlock}Friendlies block cut-through", Order = 3, RequireRestart = false,
            HintText = "{=CrestSettings_CutThroughFriendliesBlockDesc}When ON (default), a swing that would hit a friendly stops there - prevents accidental cleave on your own troops. When OFF, swings pass through allies too.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCutThrough}Combat", GroupOrder = 4)]
        public bool CutThroughFriendliesBlock { get => _cutThroughFriendliesBlock; set { if (_cutThroughFriendliesBlock != value) { _cutThroughFriendliesBlock = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_CutThroughOnlyKilled}Only killed units allow cut-through", Order = 4, RequireRestart = false,
            HintText = "{=CrestSettings_CutThroughOnlyKilledDesc}When ON, cut-through only triggers when the first target was killed by the hit. Hits that wound but don't kill stop the swing. Default OFF.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCutThrough}Combat", GroupOrder = 4)]
        public bool CutThroughOnlyKilledUnits { get => _cutThroughOnlyKilledUnits; set { if (_cutThroughOnlyKilledUnits != value) { _cutThroughOnlyKilledUnits = value; OnPropertyChanged(); } } }

        [SettingPropertyFloatingInteger("{=CrestSettings_CutThroughDamageRetained}Damage retained per cut", 0.1f, 1.0f, "0.00", Order = 5, RequireRestart = false,
            HintText = "{=CrestSettings_CutThroughDamageRetainedDesc}Fraction of the swing's momentum that carries forward into the next target. 1.0 = full damage to every target in the path; 0.5 = half damage to second target, quarter to third, and so on. Default is 0.8.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCutThrough}Combat", GroupOrder = 4)]
        public float CutThroughDamageRetainedPerCut { get => _cutThroughDamageRetainedPerCut; set { if (Math.Abs(_cutThroughDamageRetainedPerCut - value) > 0.001f) { _cutThroughDamageRetainedPerCut = value; OnPropertyChanged(); } } }

        [SettingPropertyFloatingInteger("{=CrestSettings_CutThroughArmorThreshold}Armor cut-through threshold", 0.0f, 1.0f, "0.00", Order = 6, RequireRestart = false,
            HintText = "{=CrestSettings_CutThroughArmorThresholdDesc}Minimum fraction of (inflicted / total) damage required for the cut to continue. If too much damage was absorbed by armor, the swing stops. Default is 0.5 (at least half the swing's damage must reach the target).")]
        [SettingPropertyGroup("{=CrestSettings_GroupCutThrough}Combat", GroupOrder = 4)]
        public float CutThroughArmorThreshold { get => _cutThroughArmorThreshold; set { if (Math.Abs(_cutThroughArmorThreshold - value) > 0.001f) { _cutThroughArmorThreshold = value; OnPropertyChanged(); } } }

        // ---------------------------------------------------------------
        // Group 5: Companion Swap (GroupOrder = 5)
        // Y.21-fix: was "Tactical View" -- renamed to "Companion Swap" so
        // the group is discoverable right next to Combat. The master toggle
        // here is "Enable companion swap" and is the documented in-battle
        // on/off switch (paired with the Numpad * hotkey).
        // ---------------------------------------------------------------
        [SettingPropertyBool("{=CrestSettings_EnableCompanionHotswap}Enable companion swap", Order = 0, IsToggle = true, RequireRestart = false,
            HintText = "{=CrestSettings_EnableCompanionHotswapDesc}Master switch for in-battle companion swap (a.k.a. tactical view). When ON, hold the configured hotkey (default Numpad *) during a battle to bring up a companion roster with screen-space markers, then click any companion to instantly take control of them. Time slows while the menu is open. Takes effect on the next battle - no restart required.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCompanionSwap}Companion Swap", GroupOrder = 5)]
        public bool EnableCompanionHotswap { get => _enableCompanionHotswap; set { if (_enableCompanionHotswap != value) { _enableCompanionHotswap = value; OnPropertyChanged(); } } }

        // ---------------------------------------------------------------
        // Group 5b: Cinema Tools (GroupOrder = 5, sub-group)
        // Y.29: Item + Troop spawner buttons for Cinema mode. Master
        // toggle gates the buttons. Default OFF; Cinema preset turns it ON.
        // ---------------------------------------------------------------
        [SettingPropertyBool("{=CrestSettings_EnableCinemaTools}Enable cinema tools", Order = 0, IsToggle = true, RequireRestart = false,
            HintText = "{=CrestSettings_EnableCinemaToolsDesc}Master toggle for the Cinema Tools section. When ON, exposes spawner buttons that toggle vanilla cheat mode and open Inventory/Party screens. Designed for Cinema/recording sessions where you want to set up specific scenarios.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCinemaTools}Cinema Tools", GroupOrder = 6)]
        public bool EnableCinemaTools { get => _enableCinemaTools; set { if (_enableCinemaTools != value) { _enableCinemaTools = value; OnPropertyChanged(); } } }

        [SettingPropertyButton("{=CrestSettings_ItemSpawner}Item spawner", Content = "Open inventory in cheat mode", Order = 1, RequireRestart = false,
            HintText = "{=CrestSettings_ItemSpawnerDesc}Enables vanilla cheat mode and opens the Inventory screen, where any item in the game becomes available. Click 'Cheat mode OFF' below when done.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCinemaTools}Cinema Tools", GroupOrder = 6)]
        public Action ItemSpawner { get; set; } = () =>
        {
            CrestSettings_CinemaTools_TryOpenItemSpawner();
        };

        [SettingPropertyButton("{=CrestSettings_TroopSpawner}Troop spawner", Content = "Open party in cheat mode", Order = 2, RequireRestart = false,
            HintText = "{=CrestSettings_TroopSpawnerDesc}Enables vanilla cheat mode and opens the Party screen, where every troop type becomes recruitable from the cheat-mode left-side list. Click 'Cheat mode OFF' below when done. (Default cheat mode shows 10 of each troop -- a 100-each patch is filed for follow-up.)")]
        [SettingPropertyGroup("{=CrestSettings_GroupCinemaTools}Cinema Tools", GroupOrder = 6)]
        public Action TroopSpawner { get; set; } = () =>
        {
            CrestSettings_CinemaTools_TryOpenTroopSpawner();
        };

        [SettingPropertyButton("{=CrestSettings_DisableCheatMode}Cheat mode OFF", Content = "Disable cheat mode", Order = 3, RequireRestart = false,
            HintText = "{=CrestSettings_DisableCheatModeDesc}Disables vanilla cheat mode. Click this when you're done spawning items/troops so you don't accidentally trigger cheat-mode UI in normal play.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCinemaTools}Cinema Tools", GroupOrder = 6)]
        public Action DisableCheatMode { get; set; } = () =>
        {
            CrestSettings_CinemaTools_TrySetCheatMode(false);
            try { TaleWorlds.Library.InformationManager.DisplayMessage(new TaleWorlds.Library.InformationMessage("Cheat mode disabled.", TaleWorlds.Library.Color.FromUint(0xFF66BB44))); } catch { }
        };

        [SettingPropertyFloatingInteger("{=CrestSettings_CompanionHotswapTimeSlow}Time-slow factor", 0.05f, 1.0f, "0.00", Order = 2, RequireRestart = false,
            HintText = "{=CrestSettings_CompanionHotswapTimeSlowDesc}Fraction of normal time speed while the companion-swap menu is open. 0.15 = 15% (default). 1.0 disables the time-slow entirely.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCompanionSwap}Companion Swap", GroupOrder = 5)]
        public float CompanionHotswapTimeSlowFactor { get => _companionHotswapTimeSlowFactor; set { if (Math.Abs(_companionHotswapTimeSlowFactor - value) > 0.001f) { _companionHotswapTimeSlowFactor = value; OnPropertyChanged(); } } }

        // ---------------------------------------------------------------
        // Group 6: Campaign Tweaks (GroupOrder = 6)
        // ---------------------------------------------------------------
        [SettingPropertyBool("{=CrestSettings_EnableCampaignTweaks}Enable campaign tweaks", Order = 0, IsToggle = true, RequireRestart = false,
            HintText = "{=CrestSettings_EnableCampaignTweaksDesc}Master switch for the curated set of small QoL Harmony patches below. Each individual feature has its own toggle and defaults OFF, so flipping the master on doesn't change anything until you opt into specific tweaks.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public bool EnableCampaignTweaks { get => _enableCampaignTweaks; set { if (_enableCampaignTweaks != value) { _enableCampaignTweaks = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_PreventClanDeath}Prevent natural deaths in clans", Order = 2, RequireRestart = false,
            HintText = "{=CrestSettings_PreventClanDeathDesc}Heroes never die of old age. Combine with the player-only toggle below to limit it to your clan.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public bool PreventClanDeath { get => _preventClanDeath; set { if (_preventClanDeath != value) { _preventClanDeath = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_PreventClanDeathPlayerOnly}...only for the player clan", Order = 3, RequireRestart = false,
            HintText = "{=CrestSettings_PreventClanDeathPlayerOnlyDesc}When ON, only player-clan heroes are immortal. When OFF, every clan benefits.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public bool PreventClanDeathPlayerOnly { get => _preventClanDeathPlayerOnly; set { if (_preventClanDeathPlayerOnly != value) { _preventClanDeathPlayerOnly = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_PlayerNoFlinch}No flinch on player team (partial)", Order = 4, RequireRestart = false,
            HintText = "{=CrestSettings_PlayerNoFlinchDesc}Player-team agents don't get staggered or stunned by hits. Currently only partial -- ref-struct patch limitation. Logs once at first hit if it can't fully apply.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public bool PlayerNoFlinch { get => _playerNoFlinch; set { if (_playerNoFlinch != value) { _playerNoFlinch = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_NoExecutionPenalty}No relation penalty when player executes", Order = 5, RequireRestart = false,
            HintText = "{=CrestSettings_NoExecutionPenaltyDesc}Suppresses relation drops with other clans when the player executes a hero. Useful if you want to roleplay a tyrant without the diplomacy fallout.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public bool NoExecutionPenalty { get => _noExecutionPenalty; set { if (_noExecutionPenalty != value) { _noExecutionPenalty = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_ClanTournamentExclusion}Exclude player-clan companions from arena", Order = 6, RequireRestart = false,
            HintText = "{=CrestSettings_ClanTournamentExclusionDesc}When ON, your clan's companions never appear as tournament opponents. The main hero can still participate normally.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public bool ClanTournamentExclusion { get => _clanTournamentExclusion; set { if (_clanTournamentExclusion != value) { _clanTournamentExclusion = value; OnPropertyChanged(); } } }

        [SettingPropertyFloatingInteger("{=CrestSettings_ClanPartySpeedBonus}Player-clan party speed bonus", 0f, 5f, "0.0", Order = 7, RequireRestart = false,
            HintText = "{=CrestSettings_ClanPartySpeedBonusDesc}Flat speed bonus added to every player-clan party (your party + companion parties). 0 = off. 1.0 is meaningful, 3.0 is a lot.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public float ClanPartySpeedBonus { get => _clanPartySpeedBonus; set { if (Math.Abs(_clanPartySpeedBonus - value) > 0.001f) { _clanPartySpeedBonus = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_StopPrisonerEscape}Captured heroes never escape", Order = 8, RequireRestart = false,
            HintText = "{=CrestSettings_StopPrisonerEscapeDesc}Suppresses the daily/hourly random-escape rolls for prisoner heroes. They stay captured until you ransom or free them.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public bool StopPrisonerEscape { get => _stopPrisonerEscape; set { if (_stopPrisonerEscape != value) { _stopPrisonerEscape = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_LootCapturedHeroes}Loot items off captured heroes (placeholder)", Order = 9, RequireRestart = false,
            HintText = "{=CrestSettings_LootCapturedHeroesDesc}Toggle wired but inert until Y.5c -- requires hard type refs to InventoryHelper + EquipmentElement. Logs once when triggered.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public bool LootCapturedHeroes { get => _lootCapturedHeroes; set { if (_lootCapturedHeroes != value) { _lootCapturedHeroes = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_EnablePlayerHealthRegen}Player team passive health regen", Order = 10, RequireRestart = false,
            HintText = "{=CrestSettings_EnablePlayerHealthRegenDesc}Player-team agents regenerate health each second during regular battles. Skipped during tournaments. Rate adjustable below.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public bool EnablePlayerHealthRegen { get => _enablePlayerHealthRegen; set { if (_enablePlayerHealthRegen != value) { _enablePlayerHealthRegen = value; OnPropertyChanged(); } } }

        [SettingPropertyFloatingInteger("{=CrestSettings_PlayerHealthRegenPerSec}Health regen rate (HP/sec)", 0f, 25f, "0.0", Order = 11, RequireRestart = false,
            HintText = "{=CrestSettings_PlayerHealthRegenPerSecDesc}HP restored per second when the regen toggle above is ON. Default 1.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public float PlayerHealthRegenPerSec { get => _playerHealthRegenPerSec; set { if (Math.Abs(_playerHealthRegenPerSec - value) > 0.001f) { _playerHealthRegenPerSec = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_NoArrowsStuck}No arrows stuck in agents (placeholder)", Order = 12, RequireRestart = false,
            HintText = "{=CrestSettings_NoArrowsStuckDesc}Toggle wired but inert until Y.5c -- requires ref-struct mutation we don't have without hard TaleWorlds.MountAndBlade reference.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public bool NoArrowsStuck { get => _noArrowsStuck; set { if (_noArrowsStuck != value) { _noArrowsStuck = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_MarriageStaysInClan}Married-in spouse joins your clan", Order = 13, RequireRestart = false,
            HintText = "{=CrestSettings_MarriageStaysInClanDesc}When a player-clan hero marries, the spouse joins the player clan instead of the player's hero leaving. Useful for keeping daughters as heirs.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public bool MarriageStaysInClan { get => _marriageStaysInClan; set { if (_marriageStaysInClan != value) { _marriageStaysInClan = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_PregnancyChanceUncapped}Floor pregnancy chance per cycle", Order = 14, RequireRestart = false,
            HintText = "{=CrestSettings_PregnancyChanceUncappedDesc}Vanilla decays pregnancy chance to near-zero after a few children. When ON, the floor below is enforced so further pregnancies are still possible.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public bool PregnancyChanceUncapped { get => _pregnancyChanceUncapped; set { if (_pregnancyChanceUncapped != value) { _pregnancyChanceUncapped = value; OnPropertyChanged(); } } }

        [SettingPropertyFloatingInteger("{=CrestSettings_PregnancyMinChance}Pregnancy minimum chance", 0.01f, 0.5f, "0.00", Order = 15, RequireRestart = false,
            HintText = "{=CrestSettings_PregnancyMinChanceDesc}The minimum daily pregnancy chance applied when the toggle above is ON. Default 0.05 (5%).")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public float PregnancyMinChance { get => _pregnancyMinChance; set { if (Math.Abs(_pregnancyMinChance - value) > 0.001f) { _pregnancyMinChance = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_UnlockAllSmithingRecipes}Unlock all smithing recipes", Order = 16, RequireRestart = false,
            HintText = "{=CrestSettings_UnlockAllSmithingRecipesDesc}Treats every smithing recipe / part as already discovered, so you can craft anything you've seen on a sample weapon without grinding to unlock it.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public bool UnlockAllSmithingRecipes { get => _unlockAllSmithingRecipes; set { if (_unlockAllSmithingRecipes != value) { _unlockAllSmithingRecipes = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_LifelongLearning}Skill XP floor", Order = 17, RequireRestart = false,
            HintText = "{=CrestSettings_LifelongLearningDesc}Floor the learning rate so heroes always gain at least some XP from skill use, even past the level/skill cap. Default floor 0.5 (50%).")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public bool LifelongLearning { get => _lifelongLearning; set { if (_lifelongLearning != value) { _lifelongLearning = value; OnPropertyChanged(); } } }

        [SettingPropertyFloatingInteger("{=CrestSettings_LifelongLearningMinRate}Learning rate floor", 0.1f, 1.0f, "0.00", Order = 18, RequireRestart = false,
            HintText = "{=CrestSettings_LifelongLearningMinRateDesc}Minimum learning rate when the toggle above is ON. 0.5 = 50% of the unbuffed rate.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public float LifelongLearningMinRate { get => _lifelongLearningMinRate; set { if (Math.Abs(_lifelongLearningMinRate - value) > 0.001f) { _lifelongLearningMinRate = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_EnableAchievementsWithMods}Allow Steam achievements with mods loaded", Order = 19, RequireRestart = false,
            HintText = "{=CrestSettings_EnableAchievementsWithModsDesc}Suppresses Campaign.IsCheating so Steam achievements still register even with CREST and other mods loaded. Use at your own risk; some mods grant cheats that should disqualify you.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public bool EnableAchievementsWithMods { get => _enableAchievementsWithMods; set { if (_enableAchievementsWithMods != value) { _enableAchievementsWithMods = value; OnPropertyChanged(); } } }

        [SettingPropertyInteger("{=CrestSettings_TavernCompanionMultiplier}Tavern companion spawn multiplier", 1, 5, "{0}x", Order = 20, RequireRestart = false,
            HintText = "{=CrestSettings_TavernCompanionMultiplierDesc}Multiplier on the daily wanderer spawn rate AND the maximum companion population. 1 = vanilla, 3 = triple, etc. Higher values mean wanderers show up in tavern rotations roughly N times faster. Affected behavior: CompanionsCampaignBehavior.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public int TavernCompanionMultiplier { get => _tavernCompanionMultiplier; set { if (_tavernCompanionMultiplier != value) { _tavernCompanionMultiplier = value; OnPropertyChanged(); } } }

        // Phase Y.23: Faster Ships. NavalDLC ship parties poke along the
        // campaign map at a frustrating pace; doubling speed is a popular
        // QoL tweak and (importantly) keeps land cavalry meaningfully faster.
        [SettingPropertyBool("{=CrestSettings_EnableFasterShips}Faster ships", Order = 21, RequireRestart = false,
            HintText = "{=CrestSettings_EnableFasterShipsDesc}When ON, naval parties (those currently traveling at sea via NavalDLC) have their campaign-map speed multiplied by the slider below. Land parties are unaffected. Detection uses MobileParty.IsCurrentlyAtSea, so this is a no-op on installations without NavalDLC.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public bool EnableFasterShips { get => _enableFasterShips; set { if (_enableFasterShips != value) { _enableFasterShips = value; OnPropertyChanged(); } } }

        [SettingPropertyFloatingInteger("{=CrestSettings_FasterShipsMultiplier}Ship speed multiplier", 1.0f, 4.0f, "0.0x", Order = 22, RequireRestart = false,
            HintText = "{=CrestSettings_FasterShipsMultiplierDesc}Multiplier applied to ship party campaign-map speed when Faster Ships is on. 1.0 = vanilla (no change). 2.0 = double speed (default; the QoL sweet spot â€” ships still slower than horse cavalry). 3.0 = triple speed (verges on teleport). 4.0 = pirate-on-stimulants. Has no effect on land travel.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCampaignTweaks}Campaign Tweaks", GroupOrder = 6)]
        public float FasterShipsMultiplier { get => _fasterShipsMultiplier; set { if (Math.Abs(_fasterShipsMultiplier - value) > 0.001f) { _fasterShipsMultiplier = value; OnPropertyChanged(); } } }

        // ---------------------------------------------------------------
        // Phase Y.12: Reinforcements (GroupOrder = 4, sorts after Combat
        // alphabetically). Patches MissionSpawnSettings.CreateDefaultSpawnSettings
        // postfix to scale wave size and override interval/max-wave-count.
        // ---------------------------------------------------------------
        // Y.12d-fix21: Wave reinforcement settings removed from MCM. Battle
        // Convergence now serves the user's "reinforcement" intent (nearby
        // lords join the battle), so the wave-size scaler is redundant in
        // the UI. Backing fields + JSON read/write retained for backward
        // compat with existing crest.json files; properties downgraded to
        // private so they remain accessible to preset assignments without
        // showing in MCM.
        private bool EnableReinforcements { get => _enableReinforcements; set { _enableReinforcements = value; } }
        private float ReinforcementWaveMultiplier { get => _reinforcementWaveMultiplier; set { _reinforcementWaveMultiplier = value; } }
        private float ReinforcementIntervalSec { get => _reinforcementIntervalSec; set { _reinforcementIntervalSec = value; } }
        private int ReinforcementMaxWaves { get => _reinforcementMaxWaves; set { _reinforcementMaxWaves = value; } }

        // ---------------------------------------------------------------
        // Phase Y.12b: Battle Convergence (GroupOrder = 4, alphabetically
        // sorts after Combat and before Wave Reinforcements). Nearby AI
        // parties JOIN your battle on the campaign map -- the mechanic the
        // user actually meant when they asked for a "reinforcement system."
        //
        // NOTE for v0.9.3: the feature ships disabled at the runtime layer
        // (see Crest.Harmony's CrestBattleConvergence.AddMissionBehaviors,
        // which is a permanent no-op in this release pending v1.0.0). The
        // MCM toggles below remain visible because the UI rebuild required
        // to hide them was blocked by a NuGet .pp content-file preprocessing
        // issue for LightInject.Source; clicking the toggle does nothing
        // since the runtime ignores the flag.
        // ---------------------------------------------------------------
        [SettingPropertyBool("{=CrestSettings_EnableBattleConvergence}Nearby parties join your battle", Order = 0, IsToggle = true, RequireRestart = false,
            HintText = "{=CrestSettings_EnableBattleConvergenceDesc}When ON, allied AI parties within range of a battle automatically join the appropriate side. Allies of you join your side; allies of your enemy join the enemy side. Small skirmishes can grow into major engagements when armies are nearby. Takes effect on the NEXT battle - no restart required.")]
        [SettingPropertyGroup("{=CrestSettings_GroupBattleConvergence}Battle Convergence", GroupOrder = 4)]
        public bool EnableBattleConvergence { get => _enableBattleConvergence; set { if (_enableBattleConvergence != value) { _enableBattleConvergence = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_BattleConvergenceClanTierScaling}Progressive radius (scales with clan tier)", Order = 1, RequireRestart = false,
            HintText = "{=CrestSettings_BattleConvergenceClanTierScalingDesc}When ON (default), the convergence search radius grows with your clan tier: tier * multiplier. New clans (tier 0) get no convergence; renown progressively brings more lords to your battles. When OFF, the slider below is used as a flat radius.")]
        [SettingPropertyGroup("{=CrestSettings_GroupBattleConvergence}Battle Convergence", GroupOrder = 4)]
        public bool BattleConvergenceClanTierScaling { get => _battleConvergenceClanTierScaling; set { if (_battleConvergenceClanTierScaling != value) { _battleConvergenceClanTierScaling = value; OnPropertyChanged(); } } }

        [SettingPropertyInteger("{=CrestSettings_BattleConvergenceClanTierMultiplier}Range boost", 1, 3, "x{0}", Order = 2, RequireRestart = false,
            HintText = "{=CrestSettings_BattleConvergenceClanTierMultiplierDesc}Stretches the progressive search radius. x1 (default) is the base curve. x2 doubles the reach, x3 triples it -- useful if you want more lords to ride to your aid in late-game when your renown is high. Ignored while progressive radius is OFF.")]
        [SettingPropertyGroup("{=CrestSettings_GroupBattleConvergence}Battle Convergence", GroupOrder = 4)]
        public int BattleConvergenceClanTierMultiplier { get => _battleConvergenceClanTierMultiplier; set { if (_battleConvergenceClanTierMultiplier != value) { _battleConvergenceClanTierMultiplier = value; OnPropertyChanged(); } } }

        [SettingPropertyFloatingInteger("{=CrestSettings_BattleConvergenceRadius}Convergence radius (used only when progressive is OFF)", 5f, 500f, "0", Order = 3, RequireRestart = false,
            HintText = "{=CrestSettings_BattleConvergenceRadiusDesc}Flat search radius in campaign-map units. Active ONLY when 'Progressive radius' above is OFF. 75 = comfortable on-screen radius; 200 = continental scope (everyone in the area piles in).")]
        [SettingPropertyGroup("{=CrestSettings_GroupBattleConvergence}Battle Convergence", GroupOrder = 4)]
        public float BattleConvergenceRadius { get => _battleConvergenceRadius; set { if (Math.Abs(_battleConvergenceRadius - value) > 0.01f) { _battleConvergenceRadius = value; OnPropertyChanged(); } } }

        [SettingPropertyInteger("{=CrestSettings_BattleConvergenceMaxJoinersPerSide}Max joiners per side", 1, 20, "{0} parties", Order = 3, RequireRestart = false,
            HintText = "{=CrestSettings_BattleConvergenceMaxJoinersPerSideDesc}Cap on additional parties that can converge on each side. 3 (default) keeps things manageable; 5+ enables continent-shaping engagements. Each joiner brings its full troop roster, so multiplier here cascades into the wave-reinforcement scaler if both are on.")]
        [SettingPropertyGroup("{=CrestSettings_GroupBattleConvergence}Battle Convergence", GroupOrder = 4)]
        public int BattleConvergenceMaxJoinersPerSide { get => _battleConvergenceMaxJoinersPerSide; set { if (_battleConvergenceMaxJoinersPerSide != value) { _battleConvergenceMaxJoinersPerSide = value; OnPropertyChanged(); } } }

        // Y.12d-fix26 â€” Cinema-preset-only properties; no MCM UI attribute so
        // they don't show in the settings screen. Power users can edit them
        // directly in crest.json. Setters fire OnPropertyChanged so MCM's
        // preset-application path persists them through ReadFromCrestJson.
        public bool BattleConvergenceDisableFilters { get => _battleConvergenceDisableFilters; set { if (_battleConvergenceDisableFilters != value) { _battleConvergenceDisableFilters = value; OnPropertyChanged(); } } }
        public int BattleConvergenceMaxActiveJoiners { get => _battleConvergenceMaxActiveJoiners; set { if (_battleConvergenceMaxActiveJoiners != value) { _battleConvergenceMaxActiveJoiners = value; OnPropertyChanged(); } } }
        public int BattleConvergenceInitialDelaySec { get => _battleConvergenceInitialDelaySec; set { if (_battleConvergenceInitialDelaySec != value) { _battleConvergenceInitialDelaySec = value; OnPropertyChanged(); } } }
        public int BattleConvergenceCadenceSec { get => _battleConvergenceCadenceSec; set { if (_battleConvergenceCadenceSec != value) { _battleConvergenceCadenceSec = value; OnPropertyChanged(); } } }
        [SettingPropertyBool("{=CrestSettings_EnablePlayerInvincible}Player invincible", Order = 7, RequireRestart = false,
            HintText = "{=CrestSettings_EnablePlayerInvincibleDesc}When ON, the player main agent's health is pegged at full each tick. Damage still flinches and shows hit decals, but the player can never die. Designed for Cinema mode (recording, screenshots) -- you can stand in the middle of a 2,000-man engagement and watch the show. Default OFF.")]
        [SettingPropertyGroup("{=CrestSettings_GroupCutThrough}Combat", GroupOrder = 4)]
        public bool EnablePlayerInvincible { get => _enablePlayerInvincible; set { if (_enablePlayerInvincible != value) { _enablePlayerInvincible = value; OnPropertyChanged(); } } }

        // ---------------------------------------------------------------
        // Group 7: Troop Tier Unlocker (GroupOrder = 7)
        // ---------------------------------------------------------------
        [SettingPropertyBool("{=CrestSettings_EnableTierUnlocker}Enable troop tier unlocker", Order = 0, IsToggle = true, RequireRestart = false,
            HintText = "{=CrestSettings_EnableTierUnlockerDesc}Vanilla caps troops at tier 6. Many community troop trees go to tier 7 or 8 but can't be upgraded into or recruited as volunteers because of that cap. When ON, the cap is raised to the value below.")]
        [SettingPropertyGroup("{=CrestSettings_GroupTierUnlocker}Troop Tier Unlocker", GroupOrder = 7)]
        public bool EnableTierUnlocker { get => _enableTierUnlocker; set { if (_enableTierUnlocker != value) { _enableTierUnlocker = value; OnPropertyChanged(); } } }

        [SettingPropertyInteger("{=CrestSettings_TierUnlockerMax}Max upgrade tier", 6, 12, "Tier {0}", Order = 2, RequireRestart = false,
            HintText = "{=CrestSettings_TierUnlockerMaxDesc}Maximum tier troops can be upgraded to. Vanilla is 6; recommended 7 (default).")]
        [SettingPropertyGroup("{=CrestSettings_GroupTierUnlocker}Troop Tier Unlocker", GroupOrder = 7)]
        public int TierUnlockerMax { get => _tierUnlockerMax; set { if (_tierUnlockerMax != value) { _tierUnlockerMax = value; OnPropertyChanged(); } } }

        [SettingPropertyInteger("{=CrestSettings_TierUnlockerVolunteerMax}Max volunteer tier", 4, 12, "Tier {0}", Order = 3, RequireRestart = false,
            HintText = "{=CrestSettings_TierUnlockerVolunteerMaxDesc}Maximum tier of troops that can be recruited from villages as volunteers. Vanilla is 4; default 7. Higher values mean tier-7 troops can spawn directly in village rosters.")]
        [SettingPropertyGroup("{=CrestSettings_GroupTierUnlocker}Troop Tier Unlocker", GroupOrder = 7)]
        public int TierUnlockerVolunteerMax { get => _tierUnlockerVolunteerMax; set { if (_tierUnlockerVolunteerMax != value) { _tierUnlockerVolunteerMax = value; OnPropertyChanged(); } } }

        // ---------------------------------------------------------------
        // Group 8: CREST Sub-modules (GroupOrder = 8) -- ADVANCED
        // Master toggle ShowAdvancedSettings keeps the sub-module toggles
        // hidden by default (they're rarely touched and easy to misconfigure).
        // ---------------------------------------------------------------
        [SettingPropertyBool("{=CrestSettings_ShowAdvanced}Show advanced settings", Order = 0, IsToggle = true, RequireRestart = false,
            HintText = "{=CrestSettings_ShowAdvancedDesc}Reveal the per-sub-module toggles below (ButterLib, MCM, MCM Basic, MCM UI). Disabling any of these breaks community mods that rely on them; only flip this on if you know what you're doing.")]
        [SettingPropertyGroup("{=CrestSettings_Group}CREST Sub-modules", GroupOrder = 8)]
        public bool ShowAdvancedSettings { get => _showAdvancedSettings; set { if (_showAdvancedSettings != value) { _showAdvancedSettings = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_ButterLib}ButterLib", Order = 1, RequireRestart = true,
            HintText = "{=CrestSettings_ButterLibDesc}Enable CREST's ButterLib SubModule. Required by most community mods that use ButterLib's HotKey, DistanceMatrix, or ObjectSystem APIs. Restart required.")]
        [SettingPropertyGroup("{=CrestSettings_Group}CREST Sub-modules", GroupOrder = 8)]
        public bool ButterLib { get => _butterLib; set { if (_butterLib != value) { _butterLib = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_MCM}MCM (Mod Configuration Menu)", Order = 2, RequireRestart = true,
            HintText = "{=CrestSettings_MCMDesc}Enable CREST's MCM core. Required by community mods that expose configurable settings. Restart required.")]
        [SettingPropertyGroup("{=CrestSettings_Group}CREST Sub-modules", GroupOrder = 8)]
        public bool MCM { get => _mcm; set { if (_mcm != value) { _mcm = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_MCMBasic}MCM Basic Implementation", Order = 3, RequireRestart = true,
            HintText = "{=CrestSettings_MCMBasicDesc}Enable MCM's default settings storage backend. Disabling leaves the MCM API surface available to consumer mods but no settings get persisted. Restart required.")]
        [SettingPropertyGroup("{=CrestSettings_Group}CREST Sub-modules", GroupOrder = 8)]
        public bool MCMBasicImplementation { get => _mcmBasicImplementation; set { if (_mcmBasicImplementation != value) { _mcmBasicImplementation = value; OnPropertyChanged(); } } }

        [SettingPropertyBool("{=CrestSettings_MCMUI}MCM UI (in-game Mod Options menu)", Order = 4, RequireRestart = true,
            HintText = "{=CrestSettings_MCMUIDesc}Enable the in-game Mod Options screen. Disable as a workaround if MCM UI causes crashes on a given game version. Restart required.")]
        [SettingPropertyGroup("{=CrestSettings_Group}CREST Sub-modules", GroupOrder = 8)]
        public bool MCMUI { get => _mcmUI; set { if (_mcmUI != value) { _mcmUI = value; OnPropertyChanged(); } } }

        public override void OnPropertyChanged(string? propertyName = null)
        {
            base.OnPropertyChanged(propertyName);
            if (propertyName == LoadingComplete)
            {
                // crest.json is the source of truth at startup â€” overwrite whatever
                // MCM just deserialized from its own storage with the values that
                // were actually used to gate this run.
                try { ReadFromCrestJson(); } catch { }
            }
            else if (propertyName == SaveTriggered)
            {
                // Mirror current property values to crest.json so the next launch's
                // OnSubModuleLoad gates see the user's choice.
                try { WriteToCrestJson(); } catch { }
            }
            else if (propertyName != null && IsTrackedProperty(propertyName))
            {
                // Phase W.22: SaveTriggered doesn't reliably fire on every
                // individual checkbox / dropdown change in MCM (often only
                // on page-leave). Write-through on every tracked property
                // change so crest.json stays in sync with the MCM-displayed
                // state, otherwise the patch's runtime read could lag.
                try { WriteToCrestJson(); } catch { }
            }
        }

        private static bool IsTrackedProperty(string name)
        {
            switch (name)
            {
                case nameof(ButterLib):
                case nameof(MCM):
                case nameof(MCMBasicImplementation):
                case nameof(MCMUI):
                case nameof(ShowAdvancedSettings):
                case nameof(SkipIntroVideo):
                case nameof(SuppressMainMenuMessages):
                case nameof(EnableLogFiltering):
                case nameof(FilterSkillLogs):
                case nameof(FilterHeroEvents):
                case nameof(FilterRelationLogs):
                case nameof(FilterKingdomLogs):
                case nameof(FilterMinorBattleLogs):
                case nameof(FilterQuestLogs):
                case nameof(LogFilterScope):
                case nameof(EnableFasterTime):
                case nameof(FasterTimeUltraFastSpeed):
                case nameof(FasterTimeSuperFastSpeed):
                case nameof(FasterTimeUltraFastHotkey):
                case nameof(FasterTimeSuperFastHotkey):
                case nameof(EnableCutThroughEveryone):
                case nameof(CutThroughAlsoForAI):
                case nameof(CutThroughFriendliesBlock):
                case nameof(CutThroughOnlyKilledUnits):
                case nameof(CutThroughDamageRetainedPerCut):
                case nameof(CutThroughArmorThreshold):
                case nameof(EnableCompanionHotswap):
                case nameof(CompanionHotswapTimeSlowFactor):
                case nameof(EnableCampaignTweaks):
                case nameof(PreventClanDeath):
                case nameof(PreventClanDeathPlayerOnly):
                case nameof(PlayerNoFlinch):
                case nameof(NoExecutionPenalty):
                case nameof(ClanTournamentExclusion):
                case nameof(ClanPartySpeedBonus):
                case nameof(StopPrisonerEscape):
                case nameof(LootCapturedHeroes):
                case nameof(EnablePlayerHealthRegen):
                case nameof(PlayerHealthRegenPerSec):
                case nameof(NoArrowsStuck):
                case nameof(MarriageStaysInClan):
                case nameof(PregnancyChanceUncapped):
                case nameof(PregnancyMinChance):
                case nameof(UnlockAllSmithingRecipes):
                case nameof(LifelongLearning):
                case nameof(LifelongLearningMinRate):
                case nameof(EnableAchievementsWithMods):
                case nameof(TavernCompanionMultiplier):
                case nameof(EnableFasterShips):
                case nameof(FasterShipsMultiplier):
                case nameof(EnableReinforcements):
                case nameof(ReinforcementWaveMultiplier):
                case nameof(ReinforcementIntervalSec):
                case nameof(ReinforcementMaxWaves):
                case nameof(EnableBattleConvergence):
                case nameof(BattleConvergenceRadius):
                case nameof(BattleConvergenceMaxJoinersPerSide):
                case nameof(BattleConvergenceClanTierScaling):
                case nameof(BattleConvergenceClanTierMultiplier):
                case nameof(BattleConvergenceDisableFilters):
                case nameof(BattleConvergenceMaxActiveJoiners):
                case nameof(BattleConvergenceInitialDelaySec):
                case nameof(BattleConvergenceCadenceSec):
                case nameof(EnablePlayerInvincible):
                case nameof(EnableTierUnlocker):
                case nameof(TierUnlockerMax):
                case nameof(TierUnlockerVolunteerMax):
                    return true;
                default:
                    return false;
            }
        }

        // Walks up from this assembly's location to the CREST module root.
        // CREST.v1.4.1.dll lives at Modules\CREST\bin\Win64_Shipping_Client\
        // and crest.json sits at Modules\CREST\crest.json.
        private static string? ResolveCrestJsonPath()
        {
            try
            {
                var asmLoc = typeof(CrestSettings).Assembly.Location;
                if (string.IsNullOrEmpty(asmLoc)) return null;
                var binDir = Path.GetDirectoryName(asmLoc);
                if (binDir == null) return null;
                var binParent = Directory.GetParent(binDir);
                if (binParent == null) return null;
                var crestRoot = binParent.Parent;
                if (crestRoot == null) return null;
                return Path.Combine(crestRoot.FullName, "crest.json");
            }
            catch { return null; }
        }

        private void ReadFromCrestJson()
        {
            var path = ResolveCrestJsonPath();
            if (path == null || !File.Exists(path)) return;
            var content = File.ReadAllText(path);
            // Match the same regex CrestConfig uses so the two parsers can't disagree.
            var matches = Regex.Matches(content, "\"([A-Za-z_][A-Za-z0-9_]*)\"\\s*:\\s*(true|false)",
                RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
            foreach (Match m in matches)
            {
                var key = m.Groups[1].Value;
                var val = m.Groups[2].Value.Equals("true", StringComparison.OrdinalIgnoreCase);
                switch (key)
                {
                    case "ButterLib":              _butterLib = val; break;
                    case "MCM":                    _mcm = val; break;
                    case "MCMBasicImplementation": _mcmBasicImplementation = val; break;
                    case "MCMUI":                  _mcmUI = val; break;
                    case "ShowAdvancedSettings":   _showAdvancedSettings = val; break;
                    case "SkipIntroVideo":         _skipIntroVideo = val; break;
                    case "SuppressMainMenuMessages": _suppressMainMenuMessages = val; break;
                    case "EnableLogFiltering":     _enableLogFiltering     = val; break;
                    case "FilterSkillLogs":        _filterSkillLogs       = val; break;
                    case "FilterHeroEvents":       _filterHeroEvents      = val; break;
                    case "FilterRelationLogs":     _filterRelationLogs    = val; break;
                    case "FilterKingdomLogs":      _filterKingdomLogs     = val; break;
                    case "FilterMinorBattleLogs":  _filterMinorBattleLogs = val; break;
                    case "FilterQuestLogs":        _filterQuestLogs       = val; break;
                    case "EnableFasterTime":       _enableFasterTime          = val; break;
                    case "EnableCutThroughEveryone":   _enableCutThroughEveryone   = val; break;
                    case "CutThroughAlsoForAI":        _cutThroughAlsoForAI        = val; break;
                    case "CutThroughFriendliesBlock":  _cutThroughFriendliesBlock  = val; break;
                    case "CutThroughOnlyKilledUnits":  _cutThroughOnlyKilledUnits  = val; break;
                    case "EnableCompanionHotswap":     _enableCompanionHotswap     = val; break;
                    // Phase Y.5/Y.5b: campaign tweaks. Old RK-prefixed keys read for back-compat.
                    case "EnableCampaignTweaks":       _enableCampaignTweaks       = val; break;
                    case "EnableReaperKeeperBits":     _enableCampaignTweaks       = val; break; // legacy
                    case "PreventClanDeath":           _preventClanDeath           = val; break;
                    case "RKPreventClanDeath":         _preventClanDeath           = val; break; // legacy
                    case "PreventClanDeathPlayerOnly": _preventClanDeathPlayerOnly = val; break;
                    case "RKPreventClanDeathPlayerOnly": _preventClanDeathPlayerOnly = val; break; // legacy
                    case "PlayerNoFlinch":             _playerNoFlinch             = val; break;
                    case "RKNoFlinch":                 _playerNoFlinch             = val; break; // legacy
                    case "NoExecutionPenalty":         _noExecutionPenalty         = val; break;
                    case "RKNoExecutionPenalty":       _noExecutionPenalty         = val; break; // legacy
                    case "ClanTournamentExclusion":    _clanTournamentExclusion    = val; break;
                    case "RKTournamentExclusion":      _clanTournamentExclusion    = val; break; // legacy
                    case "StopPrisonerEscape":         _stopPrisonerEscape         = val; break;
                    case "LootCapturedHeroes":         _lootCapturedHeroes         = val; break;
                    case "EnablePlayerHealthRegen":    _enablePlayerHealthRegen    = val; break;
                    case "NoArrowsStuck":              _noArrowsStuck              = val; break;
                    case "MarriageStaysInClan":        _marriageStaysInClan        = val; break;
                    case "PregnancyChanceUncapped":    _pregnancyChanceUncapped    = val; break;
                    case "UnlockAllSmithingRecipes":   _unlockAllSmithingRecipes   = val; break;
                    case "LifelongLearning":           _lifelongLearning           = val; break;
                    case "EnableAchievementsWithMods": _enableAchievementsWithMods = val; break;
                    case "EnableFasterShips":          _enableFasterShips          = val; break;
                    case "EnableReinforcements":       _enableReinforcements       = val; break;
                    case "EnableBattleConvergence":         _enableBattleConvergence         = val; break;
                    case "BattleConvergenceClanTierScaling": _battleConvergenceClanTierScaling = val; break;
                    case "BattleConvergenceDisableFilters":  _battleConvergenceDisableFilters  = val; break;
                    case "EnablePlayerInvincible":           _enablePlayerInvincible           = val; break;
                    case "EnableCinemaTools":                _enableCinemaTools                = val; break;
                    case "EnableTierUnlocker":         _enableTierUnlocker         = val; break;
                }
            }
            // Phase Y.1: numeric values for FasterTime sliders + hotkeys.
            var nmatches = Regex.Matches(content, "\"([A-Za-z_][A-Za-z0-9_]*)\"\\s*:\\s*(-?\\d+(?:\\.\\d+)?)",
                RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
            foreach (Match m in nmatches)
            {
                var key = m.Groups[1].Value;
                if (!float.TryParse(m.Groups[2].Value, System.Globalization.NumberStyles.Float, CultureInfo.InvariantCulture, out var f)) continue;
                switch (key)
                {
                    case "FasterTimeUltraFastSpeed":  _fasterTimeUltraFastSpeed  = f; break;
                    case "FasterTimeSuperFastSpeed":  _fasterTimeSuperFastSpeed  = f; break;
                    case "FasterTimeUltraFastHotkey":
                        // Phase Y.5: migrate users who saved with the
                        // pre-Y.5 broken default codes (11=intended D4,
                        // 12=intended D5). The game's InputKey enum has
                        // D4=5 and D5=6, so 11 and 12 are nonsense codes
                        // that don't fire any key. Quietly fix.
                        var ufv = (int) f;
                        if (ufv == 12) ufv = 6;       // intended D5 -> actual D5
                        else if (ufv == 11) ufv = 5;  // intended D4 -> actual D4
                        _fasterTimeUltraFastHotkey = ufv;
                        break;
                    case "FasterTimeSuperFastHotkey":
                        var sfv = (int) f;
                        if (sfv == 11) sfv = 5;       // intended D4 -> actual D4
                        else if (sfv == 12) sfv = 6;  // intended D5 -> actual D5
                        _fasterTimeSuperFastHotkey = sfv;
                        break;
                    case "CutThroughDamageRetainedPerCut": _cutThroughDamageRetainedPerCut = f; break;
                    case "CutThroughArmorThreshold":       _cutThroughArmorThreshold       = f; break;
                    case "CompanionHotswapHotkeyLeft":     _companionHotswapHotkeyLeft     = (int) f; break;
                    case "CompanionHotswapHotkeyRight":    _companionHotswapHotkeyRight    = (int) f; break;
                    case "CompanionHotswapTimeSlowFactor": _companionHotswapTimeSlowFactor = f; break;
                    case "ClanPartySpeedBonus":            _clanPartySpeedBonus            = f; break;
                    case "RKClanSpeedBonus":               _clanPartySpeedBonus            = f; break; // legacy
                    case "PlayerHealthRegenPerSec":        _playerHealthRegenPerSec        = f; break;
                    case "PregnancyMinChance":             _pregnancyMinChance             = f; break;
                    case "LifelongLearningMinRate":        _lifelongLearningMinRate        = f; break;
                    case "TierUnlockerMax":                _tierUnlockerMax                = (int) f; break;
                    case "TierUnlockerVolunteerMax":       _tierUnlockerVolunteerMax       = (int) f; break;
                    case "TavernCompanionMultiplier":      _tavernCompanionMultiplier      = (int) f; break;
                    case "FasterShipsMultiplier":          _fasterShipsMultiplier          = f; break;
                    case "ReinforcementWaveMultiplier":     _reinforcementWaveMultiplier   = f; break;
                    case "ReinforcementIntervalSec":        _reinforcementIntervalSec      = f; break;
                    case "ReinforcementMaxWaves":           _reinforcementMaxWaves         = (int) f; break;
                    case "BattleConvergenceRadius":         _battleConvergenceRadius       = f; break;
                    case "BattleConvergenceMaxJoinersPerSide": _battleConvergenceMaxJoinersPerSide = (int) f; break;
                    case "BattleConvergenceClanTierMultiplier": _battleConvergenceClanTierMultiplier = (int) f; break;
                    case "BattleConvergenceMaxActiveJoiners":   _battleConvergenceMaxActiveJoiners   = (int) f; break;
                    case "BattleConvergenceInitialDelaySec":    _battleConvergenceInitialDelaySec    = (int) f; break;
                    case "BattleConvergenceCadenceSec":         _battleConvergenceCadenceSec         = (int) f; break;
                }
            }
            // Phase W.3: scope dropdown is string-valued. Match "key": "value"
            // and feed the LogFilterScope dropdown's SelectedValue if present.
            var smatches = Regex.Matches(content, "\"([A-Za-z_][A-Za-z0-9_]*)\"\\s*:\\s*\"([^\"]*)\"",
                RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
            foreach (Match m in smatches)
            {
                if (m.Groups[1].Value.Equals("LogFilterScope", StringComparison.OrdinalIgnoreCase))
                {
                    var v = m.Groups[2].Value;
                    // Normalize legacy short forms ("Party" -> "Party only" etc).
                    if      (v.Equals("Party", StringComparison.OrdinalIgnoreCase))   v = "Party only";
                    else if (v.Equals("Clan", StringComparison.OrdinalIgnoreCase))    v = "Clan only";
                    else if (v.Equals("Kingdom", StringComparison.OrdinalIgnoreCase)) v = "Kingdom only";
                    // Dropdown<T> derives from List<T>; use IndexOf to find
                    // and SelectedIndex to set. The setter quietly no-ops if
                    // the value isn't in the list.
                    if (LogFilterScope != null)
                    {
                        var idx = LogFilterScope.IndexOf(v);
                        if (idx >= 0) LogFilterScope.SelectedIndex = idx;
                    }
                }
            }
        }

        private void WriteToCrestJson()
        {
            var path = ResolveCrestJsonPath();
            if (path == null) return;
            var sb = new StringBuilder();
            sb.Append("{\n");
            sb.Append("  \"_comment\": \"CREST runtime configuration. Edit and relaunch the game to apply, or toggle the same checkboxes in MCM.\",\n");
            sb.Append("  \"enabled\": {\n");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"ShowAdvancedSettings\": {0},\n", _showAdvancedSettings ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"ButterLib\": {0},\n", _butterLib ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"MCM\": {0},\n", _mcm ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"MCMBasicImplementation\": {0},\n", _mcmBasicImplementation ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"MCMUI\": {0},\n", _mcmUI ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"SkipIntroVideo\": {0},\n", _skipIntroVideo ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"SuppressMainMenuMessages\": {0},\n", _suppressMainMenuMessages ? "true" : "false");
            // Phase W.4: master toggle (gates everything below)
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"EnableLogFiltering\": {0},\n",     _enableLogFiltering    ? "true" : "false");
            // Phase W: campaign log filter buckets
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"FilterSkillLogs\": {0},\n",       _filterSkillLogs       ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"FilterHeroEvents\": {0},\n",      _filterHeroEvents      ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"FilterRelationLogs\": {0},\n",    _filterRelationLogs    ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"FilterKingdomLogs\": {0},\n",     _filterKingdomLogs     ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"FilterMinorBattleLogs\": {0},\n", _filterMinorBattleLogs ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"FilterQuestLogs\": {0},\n",       _filterQuestLogs       ? "true" : "false");
            // Phase W.3: scope dropdown â€” string-valued
            var scope = LogFilterScope?.SelectedValue ?? "None";
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"LogFilterScope\": \"{0}\",\n", scope);
            // Phase Y.1: Time controls.
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"EnableFasterTime\": {0},\n",          _enableFasterTime ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"FasterTimeUltraFastSpeed\": {0},\n",  _fasterTimeUltraFastSpeed);
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"FasterTimeSuperFastSpeed\": {0},\n",  _fasterTimeSuperFastSpeed);
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"FasterTimeUltraFastHotkey\": {0},\n", _fasterTimeUltraFastHotkey);
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"FasterTimeSuperFastHotkey\": {0},\n", _fasterTimeSuperFastHotkey);
            // Phase Y.2: Cut-through swings.
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"EnableCutThroughEveryone\": {0},\n",       _enableCutThroughEveryone   ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"CutThroughAlsoForAI\": {0},\n",            _cutThroughAlsoForAI        ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"CutThroughFriendliesBlock\": {0},\n",      _cutThroughFriendliesBlock  ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"CutThroughOnlyKilledUnits\": {0},\n",      _cutThroughOnlyKilledUnits  ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"CutThroughDamageRetainedPerCut\": {0},\n", _cutThroughDamageRetainedPerCut);
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"CutThroughArmorThreshold\": {0},\n",       _cutThroughArmorThreshold);
            // Phase Y.3: Tactical view.
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"EnableCompanionHotswap\": {0},\n",         _enableCompanionHotswap ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"CompanionHotswapHotkeyLeft\": {0},\n",     _companionHotswapHotkeyLeft);
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"CompanionHotswapHotkeyRight\": {0},\n",    _companionHotswapHotkeyRight);
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"CompanionHotswapTimeSlowFactor\": {0},\n", _companionHotswapTimeSlowFactor);
            // Phase Y.5/Y.5b: Campaign Tweaks (de-RK-branded, neutral key names).
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"EnableCampaignTweaks\": {0},\n",       _enableCampaignTweaks          ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"PreventClanDeath\": {0},\n",           _preventClanDeath              ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"PreventClanDeathPlayerOnly\": {0},\n", _preventClanDeathPlayerOnly    ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"PlayerNoFlinch\": {0},\n",             _playerNoFlinch                ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"NoExecutionPenalty\": {0},\n",         _noExecutionPenalty            ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"ClanTournamentExclusion\": {0},\n",    _clanTournamentExclusion       ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"ClanPartySpeedBonus\": {0},\n",        _clanPartySpeedBonus);
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"StopPrisonerEscape\": {0},\n",         _stopPrisonerEscape            ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"LootCapturedHeroes\": {0},\n",         _lootCapturedHeroes            ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"EnablePlayerHealthRegen\": {0},\n",    _enablePlayerHealthRegen       ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"PlayerHealthRegenPerSec\": {0},\n",    _playerHealthRegenPerSec);
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"NoArrowsStuck\": {0},\n",              _noArrowsStuck                 ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"MarriageStaysInClan\": {0},\n",        _marriageStaysInClan           ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"PregnancyChanceUncapped\": {0},\n",    _pregnancyChanceUncapped       ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"PregnancyMinChance\": {0},\n",         _pregnancyMinChance);
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"UnlockAllSmithingRecipes\": {0},\n",   _unlockAllSmithingRecipes      ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"LifelongLearning\": {0},\n",           _lifelongLearning              ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"LifelongLearningMinRate\": {0},\n",    _lifelongLearningMinRate);
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"EnableAchievementsWithMods\": {0},\n", _enableAchievementsWithMods    ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"TavernCompanionMultiplier\": {0},\n",  _tavernCompanionMultiplier);
            // Phase Y.23: Faster Ships
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"EnableFasterShips\": {0},\n",         _enableFasterShips ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"FasterShipsMultiplier\": {0},\n",     _fasterShipsMultiplier);
            // Phase Y.12: Reinforcements
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"EnableReinforcements\": {0},\n",      _enableReinforcements ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"ReinforcementWaveMultiplier\": {0},\n", _reinforcementWaveMultiplier);
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"ReinforcementIntervalSec\": {0},\n",  _reinforcementIntervalSec);
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"ReinforcementMaxWaves\": {0},\n",     _reinforcementMaxWaves);
            // Phase Y.12b: Battle Convergence
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"EnableBattleConvergence\": {0},\n",   _enableBattleConvergence ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"BattleConvergenceClanTierScaling\": {0},\n",   _battleConvergenceClanTierScaling ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"BattleConvergenceClanTierMultiplier\": {0},\n", _battleConvergenceClanTierMultiplier);
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"BattleConvergenceRadius\": {0},\n",    _battleConvergenceRadius);
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"BattleConvergenceMaxJoinersPerSide\": {0},\n", _battleConvergenceMaxJoinersPerSide);
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"BattleConvergenceDisableFilters\": {0},\n",   _battleConvergenceDisableFilters ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"BattleConvergenceMaxActiveJoiners\": {0},\n", _battleConvergenceMaxActiveJoiners);
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"BattleConvergenceInitialDelaySec\": {0},\n",  _battleConvergenceInitialDelaySec);
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"BattleConvergenceCadenceSec\": {0},\n",       _battleConvergenceCadenceSec);
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"EnablePlayerInvincible\": {0},\n",            _enablePlayerInvincible ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"EnableCinemaTools\": {0},\n",                 _enableCinemaTools ? "true" : "false");
            // Phase Y.7: Troop tier unlocker.
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"EnableTierUnlocker\": {0},\n",         _enableTierUnlocker ? "true" : "false");
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"TierUnlockerMax\": {0},\n",            _tierUnlockerMax);
            sb.AppendFormat(CultureInfo.InvariantCulture, "    \"TierUnlockerVolunteerMax\": {0}\n",    _tierUnlockerVolunteerMax);
            sb.Append("  }\n");
            sb.Append("}\n");

            // Phase W.4 atomic write: write to a sibling .tmp file then rename
            // over the target. File.WriteAllText goes through the OS in chunks
            // and a mid-write interrupt (process kill, OS shutdown, even some
            // antivirus shims) can leave the destination truncated. Atomic
            // rename guarantees readers either see the old content or the new
            // â€” never a partial mid-write.
            var content = sb.ToString();
            var tmpPath = path + ".tmp";
            try
            {
                File.WriteAllText(tmpPath, content);
                if (File.Exists(path)) File.Delete(path);
                File.Move(tmpPath, path);
            }
            catch
            {
                // Fallback to direct write if atomic rename fails (e.g. read-only fs).
                try { File.WriteAllText(path, content); } catch { }
                try { if (File.Exists(tmpPath)) File.Delete(tmpPath); } catch { }
            }
        }

        // ---------------------------------------------------------------
        // Y.22c: built-in presets.
        // MCM exposes the dropdown in the upper-left of the settings page
        // ("Custom" / preset name). With Y.22c the field defaults match the
        // Vanilla Plus baseline, so we replace MCM's auto-generated "Default"
        // (which would just be Vanilla Plus again) with two explicit presets:
        //
        //   - "Vanilla" : every CREST behavioral toggle OFF, so the only
        //     effects are the ones you can't disable (the bundle being loaded,
        //     ButterLib/MCM/MCM-UI sub-modules running). Equivalent to
        //     stock-Bannerlord behavior with CREST present but quiet.
        //   - "Vanilla Plus" : the curated baseline that's also the field
        //     default. Picking it from the dropdown is a quick way to revert
        //     to "what new users get out of the box".
        //
        // Recommended-on Vanilla Plus knobs:
        //   - SkipIntroVideo, SuppressMainMenuMessages (pure QoL)
        //   - EnableLogFiltering, scope = "Party only" (campaign log gets
        //     very noisy mid/late game)
        //   - EnableFasterTime (16x / 5x on D5 / D4)
        //   - EnableCompanionHotswap (popular feature, Numpad * default)
        //   - EnableCampaignTweaks with NoArrowsStuck + LootCapturedHeroes
        //     + LifelongLearning + EnableAchievementsWithMods
        //     + EnableFasterShips at 2.0x
        //   - EnableTierUnlocker with cap 7
        //
        // Vanilla Plus deliberately leaves OFF: cut-through (combat lethality
        // jump), PreventClanDeath / PlayerNoFlinch / NoExecutionPenalty
        // (campaign economy), EnablePlayerHealthRegen, MarriageStaysInClan,
        // PregnancyChanceUncapped, UnlockAllSmithingRecipes,
        // TavernCompanionMultiplier > 1. Those are opt-in tastes.
        // ---------------------------------------------------------------
        public override IEnumerable<ISettingsPreset> GetBuiltInPresets()
        {
            // Y.22c: do NOT yield base.GetBuiltInPresets() â€” the auto-generated
            // "Default" calls CreateNew() which now returns Vanilla Plus values,
            // so it would duplicate the Vanilla Plus preset under a different name.
            // Instead, ship two explicit presets that cover both stances.

            yield return new MemorySettingsPreset(Id, "vanilla", "{=CrestSettings_PresetVanilla}Vanilla", () =>
            {
                var s = new CrestSettings
                {
                    // Sub-modules: keep on (these are infrastructural; turning them
                    // off would break consumer mods, not "make CREST more vanilla").
                    ShowAdvancedSettings = false,
                    ButterLib = true,
                    MCM = true,
                    MCMBasicImplementation = true,
                    MCMUI = true,

                    // QoL: leave the two pure-quality-of-life knobs ON so the
                    // game still skips the intro and doesn't paint the menu in
                    // rainbow text. Anyone who wants the TaleWorlds intro can
                    // flip SkipIntroVideo off individually.
                    SkipIntroVideo           = true,
                    SuppressMainMenuMessages = true,

                    // Every behavioral toggle OFF â€” vanilla Bannerlord.
                    EnableLogFiltering         = false,
                    EnableFasterTime           = false,
                    EnableCutThroughEveryone   = false,
                    EnableCompanionHotswap     = false,
                    EnableCampaignTweaks       = false,
                    NoArrowsStuck              = false,
                    LootCapturedHeroes         = false,
                    LifelongLearning           = false,
                    // Y.12d-fix22: NEVER turn off EnableAchievementsWithMods even
                    // in the strict Vanilla preset. With it off, AchievementsCampaignBehavior.
                    // DeactivateAchievements is allowed to fire any time the engine
                    // detects a "cheat" -- which incorrectly trips on benign things
                    // like opening the MCM screen mid-mission. The toggle is a
                    // safety net, not a feature switch; keep it on regardless of preset.
                    EnableAchievementsWithMods = true,
                    EnableFasterShips          = false,
                    FasterShipsMultiplier      = 1.0f,
                    EnableReinforcements       = false,
                    EnableBattleConvergence    = false,
                    EnableTierUnlocker         = false,
                };

                // Reset the scope dropdown to "None" (vanilla = no filtering anyway).
                try
                {
                    var idx = s.LogFilterScope?.IndexOf("None") ?? -1;
                    if (idx >= 0 && s.LogFilterScope != null)
                        s.LogFilterScope.SelectedIndex = idx;
                }
                catch { /* best-effort */ }

                return s;
            });

            // Y.22d: this preset was originally "Vanilla Plus". Renamed to
            // "Default" because (a) the field defaults match it, so a fresh
            // install IS this preset by definition, and (b) MCM's preset
            // dropdown often opens showing whichever preset alphabetically
            // sorts first when the current state matches multiple. With
            // "Default" sorting before "Vanilla" the dropdown defaults to
            // the curated baseline rather than the all-off preset.
            yield return new MemorySettingsPreset(Id, "balanced", "{=CrestSettings_PresetDefault}Default", () =>
            {
                var s = new CrestSettings
                {
                    // Sub-modules: leave at default-on; advanced toggle stays hidden.
                    ShowAdvancedSettings = false,
                    ButterLib = true,
                    MCM = true,
                    MCMBasicImplementation = true,
                    MCMUI = true,

                    // QoL
                    SkipIntroVideo           = true,
                    SuppressMainMenuMessages = true,

                    // Log filter: master ON, scope set below.
                    EnableLogFiltering = true,
                    FilterSkillLogs       = true,
                    FilterHeroEvents      = true,
                    FilterRelationLogs    = true,
                    FilterKingdomLogs     = true,
                    FilterMinorBattleLogs = true,
                    FilterQuestLogs       = true,

                    // Time controls
                    EnableFasterTime         = true,
                    FasterTimeUltraFastSpeed = 16f,
                    FasterTimeSuperFastSpeed = 5f,
                    FasterTimeUltraFastHotkey = 5,
                    FasterTimeSuperFastHotkey = 4,

                    // Combat master toggle ON; sub-settings keep defaults
                    // (only player cuts through, friendlies block, etc).
                    EnableCutThroughEveryone = true,

                    // Tactical view: companion hotswap on.
                    EnableCompanionHotswap         = true,

                    // Campaign tweaks: master ON, no-brainer picks plus
                    // LifelongLearning + EnableAchievementsWithMods.
                    EnableCampaignTweaks       = true,
                    NoArrowsStuck              = true,
                    LootCapturedHeroes         = true,
                    LifelongLearning           = true,
                    LifelongLearningMinRate    = 0.5f,
                    EnableAchievementsWithMods = true,
                    EnableFasterShips          = true,
                    FasterShipsMultiplier      = 2.0f,

                    // Reinforcements: ON at 1.5x waves with vanilla interval / max-count.
                    // Battles feel meatier without dragging on; sentinel -1 keeps interval
                    // and max-count at TaleWorlds defaults.
                    EnableReinforcements        = true,
                    ReinforcementWaveMultiplier = 1.5f,

                    // Battle Convergence: nearby allied parties join your battle.
                    // Modest defaults (25 unit radius, 3 joiners per side cap)
                    // turn small skirmishes into bigger engagements when armies
                    // are nearby, without flooding solo encounters.
                    EnableBattleConvergence            = true,
                    // Y.12d-fix19: progressive radius is the default model.
                    // The base per-tier value is a fixed engine constant
                    // (BASE_PER_TIER = 25). The Range Boost multiplies it:
                    // x1 (default) = base curve, x2 doubles, x3 triples.
                    BattleConvergenceClanTierScaling   = true,
                    BattleConvergenceClanTierMultiplier = 1,    // x1 = default
                    BattleConvergenceRadius            = 75f,   // unused while ClanTierScaling=true
                    BattleConvergenceMaxJoinersPerSide = 3,

                    // Tier unlocker: ON at tier 7 cap (modded troops typically max at 7-8).
                    EnableTierUnlocker       = true,
                    TierUnlockerMax          = 7,
                    TierUnlockerVolunteerMax = 7,
                };

                // Scope dropdown: select "Party only" (index 2 in the list at line 243+).
                try
                {
                    var idx = s.LogFilterScope?.IndexOf("Party only") ?? -1;
                    if (idx >= 0 && s.LogFilterScope != null)
                        s.LogFilterScope.SelectedIndex = idx;
                }
                catch { /* best-effort */ }

                return s;
            });

            // Y.12d-fix26: "Cinema" preset â€” the most chaotic, theatrical baseline.
            // Built on top of Default's QoL stack, but cranks Battle Convergence
            // to "every party in Calradia joins your fight" and makes the player
            // hero unkillable so they can stand in the middle of a 2,000-man
            // engagement and actually watch the show.
            //
            // Bundle of every change since Y.12d-fix23:
            //   * staggered arrivals: first lord at +45s, then 1 lord/sec
            //   * filters off (no kingdom/bandit/distance gating)
            //   * 100 joiners per side cap, 100 active simultaneously
            //   * player hero invincible (HP pegged each tick)
            yield return new MemorySettingsPreset(Id, "default", "{=CrestSettings_PresetCinema}Cinema", () =>
            {
                var s = new CrestSettings
                {
                    // Sub-modules + QoL â€” same as Default
                    ShowAdvancedSettings = false,
                    ButterLib = true,
                    MCM = true,
                    MCMBasicImplementation = true,
                    MCMUI = true,
                    SkipIntroVideo           = true,
                    SuppressMainMenuMessages = true,
                    EnableLogFiltering = true,
                    FilterSkillLogs       = true,
                    FilterHeroEvents      = true,
                    FilterRelationLogs    = true,
                    FilterKingdomLogs     = true,
                    FilterMinorBattleLogs = true,
                    FilterQuestLogs       = true,

                    // Combat / battle QoL on Default's baseline
                    EnableFasterTime         = true,
                    FasterTimeUltraFastSpeed = 16f,
                    FasterTimeSuperFastSpeed = 5f,
                    FasterTimeUltraFastHotkey = 5,
                    FasterTimeSuperFastHotkey = 4,
                    // Combat master toggle ON; sub-settings keep defaults
                    // (only player cuts through, friendlies block, etc).
                    EnableCutThroughEveryone = true,
                    EnableCompanionHotswap   = true,
                    EnableCampaignTweaks     = true,
                    NoArrowsStuck            = true,
                    LootCapturedHeroes       = true,
                    LifelongLearning         = true,
                    LifelongLearningMinRate  = 0.5f,
                    EnableAchievementsWithMods = true,
                    EnableFasterShips        = true,
                    FasterShipsMultiplier    = 2.0f,
                    EnableReinforcements     = false,    // vanilla wave settings flow through

                    // *** The cinematic stack ***
                    // Y.12d-fix31: per user â€” fast onset (5s), 3s cadence, fill until
                    // engine cap. Caps raised back to 20 because the underlying crash
                    // root cause (per-class formation explosion) is fixed in Crest.Harmony
                    // (single formation per lord instead of 3 sub-formations). Engine
                    // agent-count capGuard at 2010 will pause spawning when approaching
                    // BattleSize hard limit.
                    EnableBattleConvergence            = true,
                    BattleConvergenceDisableFilters    = false,
                    BattleConvergenceMaxJoinersPerSide = 6,
                    BattleConvergenceMaxActiveJoiners  = 6,
                    BattleConvergenceInitialDelaySec   = 5,       // first lord at +5s
                    BattleConvergenceCadenceSec        = 3,       // one lord every 3s
                    BattleConvergenceClanTierScaling   = false,
                    BattleConvergenceRadius            = 100f,
                    EnablePlayerInvincible             = true,
                    EnableCinemaTools                  = true,

                    // Tier unlocker
                    EnableTierUnlocker       = true,
                    TierUnlockerMax          = 7,
                    TierUnlockerVolunteerMax = 7,
                };

                // Scope dropdown: select "Party only" (same as Default â€” log spam mitigation).
                try
                {
                    var idx = s.LogFilterScope?.IndexOf("Party only") ?? -1;
                    if (idx >= 0 && s.LogFilterScope != null)
                        s.LogFilterScope.SelectedIndex = idx;
                }
                catch { /* best-effort */ }

                return s;
            });
        }
    }
}
