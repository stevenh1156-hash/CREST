using Bannerlord.BUTR.Shared.Helpers;

using HarmonyLib;
using HarmonyLib.BUTR.Extensions;

using System;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

using TaleWorlds.InputSystem;
using TaleWorlds.Library;
using TaleWorlds.Localization;
using TaleWorlds.MountAndBlade;

using Path = System.IO.Path;

namespace Bannerlord.Harmony;

public class SubModule : MBSubModuleBase
{
    private const uint COLOR_RED = 0xFF0000;
    private const uint COLOR_ORANGE = 0xFF8000;

    // We can't rely on EN since the game assumes that the default locale is always English
    private const string SWarningTitle = "{=qZXqV8GzUH}Warning from CREST!";
    private const string SErrorHarmonyNotFound = "{=EEVJa5azpB}CREST module was not found!";
    private const string SErrorHarmonyNotFirst = "{=NxkNTUUV32}CREST is not first in loading order!{EXPECT_ISSUES_WARNING}";

    private const string SErrorHarmonyWrongVersion = "{=Z4d2nSD38a}Loaded 0Harmony.dll version is wrong!{NL}Expected {P_VERSION}, but got {E_VERSION}!{EXPECT_ISSUES_WARNING}";
    private const string SErrorHarmonyLoadedFromAnotherPlace = "{=ASjx7sqkJs}0Harmony.dll was loaded from another location: {LOCATION}!{NL}It may be caused by a custom launcher or some other mod!{EXPECT_ISSUES_WARNING}";

    private const string SWarningExpectIssues = "{=xTeLdSrXk4}{NL}This is not recommended. Expect issues!{NL}If your game crashes and you had this warning, please, mention it in the bug report!";

    private const string SWarningMinVersion = "{=jhD6BVx78D}The current game version {GAME_VERSION} is not supported! Please upgrade your game to {MIN_GAME_VERSION} or higher!{EXPECT_ISSUES_WARNING}";

    private static readonly HarmonyRef Harmony = new("Bannerlord.Harmony.GauntletUISubModule");
    private static readonly HarmonyRef Harmony2 = new("Bannerlord.Harmony.UnpatchAll");

    private readonly DebugUI _debugUI = new();

    private static TextObject? GetExpectIssuesWarning() => new TextObject(SWarningExpectIssues).SetTextVariable("NL", Environment.NewLine);

    protected override void OnSubModuleLoad()
    {
        base.OnSubModuleLoad();

        ValidateHarmony();

        Harmony2.Patch(
            SymbolExtensions2.GetMethodInfo((HarmonyLib.Harmony x) => x.UnpatchAll(null)),
            prefix: new HarmonyMethod(typeof(SubModule), nameof(UnpatchAllPrefix)));

        // CREST early hardening: strip Zone.Identifier ADS from every DLL/EXE
        // under Modules\X\bin\ and game's bin\Win64_Shipping_Client\ so the
        // CLR doesn't refuse to load downloaded mods. Runs before any other
        // Crest.* sub-module's OnSubModuleLoad fires (Harmony loads first by
        // load order), so community mod assemblies that haven't been touched
        // yet get unblocked in time.
        CrestUnblock.Run();

        // CREST Phase N: self-heal the four Bannerlord.X stub folders if any
        // are missing or disabled in LauncherData.xml. Pairs with the BLSE
        // fork's HideCrestStubsPatch (which hides the stubs from the launcher
        // UI) and Unblock-CrestInstall.ps1 (install-time stub materialization).
        // See CrestEnsureStubs.cs for full rationale.
        CrestEnsureStubs.Run();

        // CREST QuickStart Phase J: skip TaleWorlds + Partners intro video.
        // See CrestQuickStart.cs for the patch logic and env-var opt-out.
        CrestQuickStart.Apply(new HarmonyLib.Harmony("crest.quickstart"));

        // CREST main-menu QoL: monotone color for the InformationManager
        // message stack so per-mod color choices don't paint the menu in
        // rainbow. See CrestMessageStyle.cs.
        CrestMessageStyle.Apply(new HarmonyLib.Harmony("crest.messagestyle"));

        // Phase Y.1: FasterTime absorption -- registers as a tick consumer.
        // No Harmony patches; the tick path is invoked from OnApplicationTick.
        CrestFasterTime.Apply();

        // v0.9.1: CrashMirror init — captures module start time and
        // resolves source/dest paths for crash-report mirroring. The actual
        // copy work happens on the OnApplicationTick poll.
        CrestCrashMirror.Initialize();

        // v0.9.1: probe the running game's Native module version. On Beta
        // (e1.4.x+) load Crest.Harmony.Beta.dll which contains the cavalry-
        // aware spawn limiter and Battle Convergence logic. On Public
        // (e1.3.x) the Beta DLL is never loaded; CrestBetaBridge delegates
        // stay null and the corresponding features silently no-op.
        if (CrestBetaBridge.ShouldLoadBeta())
        {
            var betaHarmony = new HarmonyLib.Harmony("crest.beta");
            CrestBetaBridge.TryLoadAndInitialize(betaHarmony);
        }
        else
        {
            CrestDiag.Log("SubModule", "Public branch detected (e1.3.x) -- Crest.Harmony.Beta.dll not loaded");
        }
    }

    protected override void OnBeforeInitialModuleScreenSetAsRoot()
    {
        base.OnBeforeInitialModuleScreenSetAsRoot();

        Harmony.Patch(
            AccessTools2.Method(typeof(MBSubModuleBase), "OnBeforeInitialModuleScreenSetAsRoot"),
            postfix: new HarmonyMethod(typeof(SubModule), nameof(OnBeforeInitialModuleScreenSetAsRootPostfix)));

        ValidateGameVersion();
    }

    public override void OnMissionBehaviorInitialize(Mission mission)
    {
        base.OnMissionBehaviorInitialize(mission);

        // Phase Y.3: CompanionHotswap absorption -- gated on master toggle,
        // adds two MissionBehaviors per mission when enabled.
        CrestCompanionHotswap.AddMissionBehaviors(mission);

        // Phase Y.12c: Battle Convergence -- nearby AI lord parties join the
        // current map event mid-mission. Clean-room rewrite of Nexus #6501
        // architecture; replaces the broken Y.12b Harmony-postfix approach.
        CrestBattleConvergence.AddMissionBehaviors(mission);

        // Phase Y.5b: player-team health regen MissionBehavior. Self-gates on
        // EnablePlayerHealthRegen per tick so adding it always is cheap.
        mission.AddMissionBehavior(new CrestPlayerTeamHealthRegen());

        // Y.12d-fix24: player invincibility MissionBehavior. Self-gates on
        // EnablePlayerInvincible per tick â€” pegs Hero.MainHero's agent at full
        // health each frame so damage still flinches/hit-decals but never kills.
        mission.AddMissionBehavior(new CrestPlayerInvincible());
    }

    // Y.12d-feature#128: hook the post-battle "rode to your aid" rescue dialogue
    // into the campaign starter. Adds the CampaignBehavior so SyncData persists
    // pending rescue thanks across save/load, and registers the dialogue lines
    // on the lord_introduction / lord_talk_speak_diplomacy_2 conversation states.
    // Self-gates on the EnableBattleConvergence config (same as the mission-side
    // logic) so disabling Convergence also silences the dialogue.
    protected override void OnGameStart(TaleWorlds.Core.Game game, TaleWorlds.Core.IGameStarter gameStarterObject)
    {
        base.OnGameStart(game, gameStarterObject);

        try
        {
            if (game?.GameType is TaleWorlds.CampaignSystem.Campaign && gameStarterObject is TaleWorlds.CampaignSystem.CampaignGameStarter starter)
            {
                if (CrestConfig.IsEnabled("EnableBattleConvergence", defaultValue: false))
                {
                    var dlg = new CrestBattleConvergenceDialogueBehavior();
                    starter.AddBehavior(dlg);
                    dlg.AddDialogs(starter);
                    CrestDiag.Log("SubModule", "Y.12d-feature#128: registered Battle Convergence rescue dialogue behavior");
                }
            }
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught("SubModule", "OnGameStart.RescueDialogue", ex);
        }
    }

    protected override void OnApplicationTick(float dt)
    {
        base.OnApplicationTick(dt);

        if ((Input.IsKeyDown(InputKey.LeftControl) || Input.IsKeyDown(InputKey.RightControl)) &&
            (Input.IsKeyDown(InputKey.LeftAlt) || Input.IsKeyDown(InputKey.RightAlt)) &&
            Input.IsKeyPressed(InputKey.H))
        {
            _debugUI.Visible = !_debugUI.Visible;
        }

        // Phase R.2: Ctrl+Alt+P captures a complete patch snapshot to
        // Modules\CREST\patches-snapshot-<timestamp>.log. Modders attach this
        // to bug reports; pairs with `Crest-Doctor.ps1 -IncludePatchSnapshot`.
        if ((Input.IsKeyDown(InputKey.LeftControl) || Input.IsKeyDown(InputKey.RightControl)) &&
            (Input.IsKeyDown(InputKey.LeftAlt) || Input.IsKeyDown(InputKey.RightAlt)) &&
            Input.IsKeyPressed(InputKey.P))
        {
            var path = CrestPatchSnapshot.Capture();
            if (!string.IsNullOrEmpty(path))
            {
                InformationManager.DisplayMessage(new InformationMessage(
                    "CREST patch snapshot saved to " + Path.GetFileName(path),
                    Color.FromUint(0xFF77CC77)));
            }
            else
            {
                InformationManager.DisplayMessage(new InformationMessage(
                    "CREST patch snapshot failed; see Modules/CREST/runtime.log",
                    Color.FromUint(0xFFCC7777)));
            }
        }

        _debugUI.Update(dt);

        // Phase Y.1: FasterTime absorption -- gated on master toggle, no-op
        // when disabled, lock-free fast path otherwise.
        CrestFasterTime.OnTick(dt);

        // v0.9.1: Preset hotkeys (Ctrl+Alt+1/2/3 → Default/Vanilla/Cinema).
        // Same Ctrl+Alt modifier shape as the existing debug-UI/snapshot
        // hotkeys so users only have to remember one chord prefix.
        if ((Input.IsKeyDown(InputKey.LeftControl) || Input.IsKeyDown(InputKey.RightControl)) &&
            (Input.IsKeyDown(InputKey.LeftAlt) || Input.IsKeyDown(InputKey.RightAlt)))
        {
            string? presetToApply = null;
            if (Input.IsKeyPressed(InputKey.D1)) presetToApply = CrestPresets.PresetDefault;
            else if (Input.IsKeyPressed(InputKey.D2)) presetToApply = CrestPresets.PresetVanilla;
            else if (Input.IsKeyPressed(InputKey.D3)) presetToApply = CrestPresets.PresetCinema;
            if (presetToApply != null)
            {
                var written = CrestPresets.Apply(presetToApply);
                if (!string.IsNullOrEmpty(written))
                    CrestPresets.NotifyApplied(presetToApply);
            }
        }

        // v0.9.1: CrashMirror tick — every N seconds, scan the BUTR
        // crashreport directory and copy any new crashreport*.html into
        // Modules\CREST\crashes\. Self-gates on EnableCrashMirror.
        CrestCrashMirror.OnTick(dt);
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void OnBeforeInitialModuleScreenSetAsRootPostfix(MBSubModuleBase __instance)
    {
        if (__instance.GetType().Name.Contains("GauntletUISubModule"))
        {
            // OnBeforeInitialModuleScreenSetAsRoot will be called before the Native modules
            // will be able to initialize the chat system we use to log info.
            ValidateLoadOrder();

            // Phase P.2: verify the top-N most version-fragile Harmony patches
            // inherited from upstream BUTR actually bound on this game version.
            // Runs at the same lifecycle point as ValidateLoadOrder so any
            // user-visible warning lands in the chat queue alongside other
            // CREST startup messages. Self-gates on crest.json's RuntimeSelfTest
            // flag (default on) and is a no-op on second invocation.
            CrestPatchSelfTest.Run();

            // Phase W: apply the campaign-log filter patch. Has to wait until
            // here because TaleWorlds.CampaignSystem doesn't load until after
            // SandBoxCore initializes, so the type wasn't resolvable at our
            // OnSubModuleLoad. TryApply is idempotent and tolerant of the
            // type still being absent (logs and bails).
            CrestCampaignLogFilter.TryApply(new HarmonyLib.Harmony("crest.campaignlogfilter"));

            // Phase Y.2: CutThroughEveryone absorption. Patches Mission and
            // MissionCombatMechanicsHelper -- both in TaleWorlds.MountAndBlade
            // which is reliably loaded by GauntletUISubModule init time.
            CrestCutThroughEveryone.TryApply(new HarmonyLib.Harmony("crest.cutthrougheveryone"));

            // Y.32 / Y.28: typed Harmony patch on Mission.RegisterBlow that
            // clamps damage to 0 for the player hero when EnablePlayerInvincible
            // is on. Hits won't register any damage. Self-gates per-call on
            // the config so it costs ~1 dictionary read per blow when off.
            CrestPlayerInvincibleDamageClamp.TryApply(new HarmonyLib.Harmony("crest.playerinvincible.clamp"));

            // Y.30 Round C-D: skip TacticComponent.SetDefaultBehaviorWeights
            // for our custom pool formations (slot >= 10) so the player team's
            // TacticCharge doesn't crash trying to set weights on behaviors
            // we don't have attached.
            CrestTacticPatch.TryApply(new HarmonyLib.Harmony("crest.tacticpatch"));

            // Y.44: swallow v1.4.3 engine AOORE in UpdateBrushesWidget (parallel
            // brush update race that hard-crashes the process under load).
            CrestBrushRacePatch.TryApply(new HarmonyLib.Harmony("crest.brushrace"));

            // Y.74: swallow v1.4.3 engine NRE in Mission.TickAgentsAndTeamsImp
            // parallel agent tick. Same shape as Y.44 -- worker-thread NRE
            // with zero CREST/mod frames in the stack. Loses one tick of
            // agent updates, gains a non-crashed game.
            CrestAgentTickFinalizer.TryApply(new HarmonyLib.Harmony("crest.agenttick"));

            // Phase Y.5/Y.5b: campaign tweaks absorption -- a curated set of
            // small QoL Harmony patches gated on EnableCampaignTweaks plus
            // per-feature toggles. (Originally absorbed from Reaper Keeper's
            // non-UI patches, but re-implemented and re-named to avoid any
            // dependency on that mod's branding.)
            CrestCampaignTweaks.TryApply(new HarmonyLib.Harmony("crest.campaigntweaks"));

            // Phase Y.11: battle-size cap lift + cavalry-aware spawn limiter.
            // Always-on; controlled by the in-game Options menu directly.
            CrestBattleSize.TryApply(new HarmonyLib.Harmony("crest.battlesize"));

            // Phase Y.7: Tier 7+ troop unlocker. Lifts the vanilla tier-6 cap on
            // DefaultCharacterStatsModel.MaxCharacterTier and DefaultVolunteerModel.MaxVolunteerTier
            // so modded high-tier troops can be upgraded into and recruited as volunteers.
            CrestTierUnlocker.TryApply(new HarmonyLib.Harmony("crest.tierunlocker"));

            Harmony.Unpatch(
                AccessTools2.Method(typeof(MBSubModuleBase), "OnBeforeInitialModuleScreenSetAsRoot"),
                HarmonyPatchType.All,
                Harmony.Id);
        }
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static bool UnpatchAllPrefix(string? harmonyID) => harmonyID is not null;

    private static void ValidateLoadOrder()
    {
        var loadedModules = ModuleInfoHelper.GetLoadedModules().ToList();
        var harmonyModule = loadedModules.SingleOrDefault(x => x.Id == "CREST");
        var harmonyModuleIndex = harmonyModule is not null ? loadedModules.IndexOf(harmonyModule) : -1;
        if (harmonyModuleIndex == -1)
            InformationManager.DisplayMessage(new InformationMessage(new TextObject(SErrorHarmonyNotFound).ToString(), Color.FromUint(COLOR_RED)));
        if (harmonyModuleIndex != 0)
        {
            var textObject = new TextObject(SErrorHarmonyNotFirst).SetTextVariable("EXPECT_ISSUES_WARNING", GetExpectIssuesWarning());
            InformationManager.DisplayMessage(new InformationMessage(textObject?.ToString() ?? "ERROR", Color.FromUint(COLOR_RED)));
        }
    }

    private static void ValidateHarmony()
    {
        var harmonyType = typeof(HarmonyMethod);

        var currentExistingHarmony = harmonyType.Assembly;
        var currentHarmonyVersion = currentExistingHarmony.GetName().Version ?? new Version(0, 0);
        var requiredHarmonyVersion = typeof(SubModule).Assembly.GetCustomAttributes<AssemblyMetadataAttribute>().FirstOrDefault(x => x.Key == "HarmonyVersion") is { } attr
            ? Version.TryParse(attr.Value, out var v)
                ? v
                : new Version(0, 0)
            : new Version(0, 0);

        var sb = new StringBuilder();
        var harmonyModule = ModuleInfoHelper.GetModuleByType(harmonyType);
        if (harmonyModule is null)
        {
            if (sb.Length != 0) sb.AppendLine();
            var textObject = new TextObject(SErrorHarmonyLoadedFromAnotherPlace);
            textObject.SetTextVariable("LOCATION", new TextObject(string.IsNullOrEmpty(currentExistingHarmony.Location) ? string.Empty : Path.GetFullPath(currentExistingHarmony.Location)));
            textObject.SetTextVariable("EXPECT_ISSUES_WARNING", GetExpectIssuesWarning());
            textObject.SetTextVariable("NL", Environment.NewLine);
            sb.AppendLine(textObject.ToString());
        }

        if (requiredHarmonyVersion.CompareTo(currentHarmonyVersion) != 0)
        {
            if (sb.Length != 0) sb.AppendLine();
            var textObject = new TextObject(SErrorHarmonyWrongVersion);
            textObject.SetTextVariable("P_VERSION", new TextObject(requiredHarmonyVersion.ToString()));
            textObject.SetTextVariable("E_VERSION", new TextObject(currentHarmonyVersion.ToString()));
            textObject.SetTextVariable("EXPECT_ISSUES_WARNING", GetExpectIssuesWarning());
            textObject.SetTextVariable("NL", Environment.NewLine);
            sb.AppendLine(textObject.ToString());
        }

        if (sb.Length > 0)
        {
            Task.Run(() => MessageBox.Show(sb.ToString(),
                new TextObject(SWarningTitle).ToString(), MessageBoxButtons.OK));
        }
    }

    private static void ValidateGameVersion()
    {
        if (ApplicationVersionHelper.GameVersion() is not { } gameVersion)
            return;

        if (!ApplicationVersionHelper.TryParse("v1.0.0", out var v100Version))
            return;

        if (!ApplicationVersionHelper.TryParse("v1.2.7", out var v127Version))
            return;

        if (ApplicationPlatform.CurrentPlatform is Platform.GDKDesktop)
        {
            if (gameVersion < v127Version)
            {
                InformationManager.DisplayMessage(new InformationMessage(new TextObject(SWarningMinVersion)
                    .SetTextVariable("GAME_VERSION", gameVersion.ToString())
                    .SetTextVariable("MIN_GAME_VERSION", v127Version.ToString())
                    .SetTextVariable("EXPECT_ISSUES_WARNING", GetExpectIssuesWarning()).ToString(), Color.FromUint(COLOR_ORANGE)));
            }
        }
        if (ApplicationPlatform.CurrentPlatform is Platform.WindowsSteam or Platform.WindowsGOG or Platform.WindowsEpic or Platform.WindowsNoPlatform or Platform.LinuxNoPlatform)
        {
            if (gameVersion < v100Version)
            {
                InformationManager.DisplayMessage(new InformationMessage(new TextObject(SWarningMinVersion)
                    .SetTextVariable("GAME_VERSION", gameVersion.ToString())
                    .SetTextVariable("MIN_GAME_VERSION", v100Version.ToString())
                    .SetTextVariable("EXPECT_ISSUES_WARNING", GetExpectIssuesWarning()).ToString(), Color.FromUint(COLOR_ORANGE)));
            }
        }
    }
}