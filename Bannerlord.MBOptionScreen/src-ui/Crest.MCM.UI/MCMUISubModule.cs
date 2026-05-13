using Bannerlord.BUTR.Shared.Helpers;
using Bannerlord.ButterLib.Common.Extensions;
using Bannerlord.ButterLib.HotKeys;
using Bannerlord.UIExtenderEx;

using BUTR.DependencyInjection;
using BUTR.DependencyInjection.ButterLib;
using BUTR.DependencyInjection.Extensions;
using BUTR.DependencyInjection.Logger;
using BUTR.MessageBoxPInvoke.Helpers;

using HarmonyLib;

using MCM.Abstractions;
using MCM.Internal.Extensions;
using MCM.UI.ButterLib;
using MCM.UI.Functionality;
using MCM.UI.Functionality.Injectors;
using MCM.UI.GUI.GauntletUI;
using MCM.UI.HotKeys;
using MCM.UI.Patches;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;

using System;
using System.Diagnostics.CodeAnalysis;
using System.Linq;
using System.Text;

using TaleWorlds.Localization;
using TaleWorlds.MountAndBlade;
using TaleWorlds.ScreenSystem;

namespace MCM.UI
{
    [SuppressMessage("CodeQuality", "IDE0079:Remove unnecessary suppression", Justification = "For ReSharper")]
    [SuppressMessage("ReSharper", "UnusedType.Global")]
    public sealed class MCMUISubModule : MBSubModuleBase
    {
        private const string SMessageContinue =
@"{=eXs6FLm5DP}It's strongly recommended to terminate the game now. Do you wish to terminate it?";
        private const string SWarningTitle =
@"{=dzeWx4xSfR}Warning from MCM!";


        private static readonly UIExtender Extender = new("MCM.UI");
        internal static ILogger<MCMUISubModule> Logger = NullLogger<MCMUISubModule>.Instance;
        internal static ResetValueToDefault? ResetValueToDefault;

        private bool DelayedServiceCreation { get; set; }
        private bool ServiceRegistrationWasCalled { get; set; }
        private bool OnBeforeInitialModuleScreenSetAsRootWasCalled { get; set; }

        public MCMUISubModule()
        {
            MCMSubModule.Instance?.OverrideServiceContainer(new ButterLibServiceContainer());

            // CREST Phase H: ValidateLoadOrder neutered — under CREST the legacy module IDs
            // are not loaded as separate modules, so MCMv5's load-order check would always fail
            // and prompt the user to terminate. The whole BUTR stack is now bundled in a single
            // CREST module so load-order is implicitly correct.
            // ValidateLoadOrder();
        }

        /// <summary>
        /// CREST Phase L gate: returns true unless config.json has the named key set to false.
        /// </summary>
        private static bool CrestEnabled(string key)
        {
            try
            {
                var t = System.Type.GetType("Bannerlord.Harmony.CrestConfig, Crest.Harmony");
                if (t == null) return true;
                var m = t.GetMethod("IsEnabled", new[] { typeof(string), typeof(bool) });
                if (m == null) return true;
                return (bool) m.Invoke(null, new object[] { key, true });
            }
            catch { return true; }
        }

        public void OnServiceRegistration()
        {
            ServiceRegistrationWasCalled = true;

            if (this.GetServiceContainer() is { } services)
            {
                services.AddSettingsContainer<ButterLibSettingsContainer>();

                services.AddTransient(typeof(IServiceProvider), () => this.GetTempServiceProvider() ?? this.GetServiceProvider()!);
                services.AddTransient<IBUTRLogger, LoggerWrapper>();
                services.AddTransient(typeof(IBUTRLogger<>), typeof(LoggerWrapper<>));


                services.AddTransient<IMCMOptionsScreen, ModOptionsGauntletScreen>();

                services.AddSingleton<BaseGameMenuScreenHandler, DefaultGameMenuScreenHandler>();
                services.AddSingleton<ResourceInjector, DefaultResourceInjector>();
            }
        }

        protected override void OnSubModuleLoad()
        {
            base.OnSubModuleLoad();

            // CREST Phase H gate: respect Modules\CREST\crest.json "MCMUI" flag.
            // Lets a user disable just MCM UI (Phase D.4 partial mitigation) without
            // disabling the rest of CREST.
            if (!CrestEnabled("MCMUI")) return;

            IServiceProvider serviceProvider;

            if (!ServiceRegistrationWasCalled)
            {
                OnServiceRegistration();
                DelayedServiceCreation = true;
                serviceProvider = this.GetTempServiceProvider()!;
            }
            else
            {
                serviceProvider = this.GetServiceProvider()!;
            }

            Logger = serviceProvider.GetRequiredService<ILogger<MCMUISubModule>>();
            Logger.LogTrace("OnSubModuleLoad: Logging started...");

            // CREST Phase H: each Patch() call reflects against TaleWorlds types
            // that may have moved or vanished in newer game versions. Upstream
            // BUTR's MCM is built per-game-version; CREST ships a single build
            // and must tolerate signature drift. Wrap each patcher so a single
            // missing target doesn't poison the rest.
            try
            {
                var optionsGauntletScreenHarmony = new Harmony("MCM.ui.optionsgauntletscreenpatch");
                try { OptionsGauntletScreenPatch.Patch(optionsGauntletScreenHarmony); }
                catch (Exception ex) { Logger?.LogError(ex, "OptionsGauntletScreenPatch failed"); }
                try { MissionGauntletOptionsUIHandlerPatch.Patch(optionsGauntletScreenHarmony); }
                catch (Exception ex) { Logger?.LogError(ex, "MissionGauntletOptionsUIHandlerPatch failed"); }

                var optionsSwitchHarmony = new Harmony("MCM.ui.optionsswitchpatch");
                try { OptionsVMPatch.Patch(optionsSwitchHarmony); }
                catch (Exception ex) { Logger?.LogError(ex, "OptionsVMPatch failed"); }
            }
            catch (Exception ex)
            {
                Logger?.LogError(ex, "MCMUISubModule.OnSubModuleLoad: harmony setup failed");
            }
        }

        protected override void OnBeforeInitialModuleScreenSetAsRoot()
        {
            base.OnBeforeInitialModuleScreenSetAsRoot();

            // CREST gate: same as OnSubModuleLoad.
            if (!CrestEnabled("MCMUI")) return;

            if (!OnBeforeInitialModuleScreenSetAsRootWasCalled)
            {
                OnBeforeInitialModuleScreenSetAsRootWasCalled = true;

                if (DelayedServiceCreation)
                {
                    Logger = this.GetServiceProvider().GetRequiredService<ILogger<MCMUISubModule>>();
                }

                // CREST Phase D.4 mitigation: each of these calls touches game UI
                // internals and is the most likely point for a hard CTD on a
                // mismatched game version. Wrap each one separately so a failure
                // in (e.g.) ResourceInjector doesn't take the game down with it
                // and we get a stack trace in the log instead of an unhandled
                // exception. The user sees a degraded MCM (no in-game options
                // menu) but the game keeps running.
                try
                {
                    Extender.Register(typeof(MCMUISubModule).Assembly);
                    Extender.Enable();
                }
                catch (Exception ex) { Logger?.LogError(ex, "MCM UI: UIExtenderEx.Enable failed"); }

                try
                {
                    if (HotKeyManager.Create("MCM.UI") is { } hkm)
                    {
                        ResetValueToDefault = hkm.Add<ResetValueToDefault>();
                        hkm.Build();
                    }
                }
                catch (Exception ex) { Logger?.LogError(ex, "MCM UI: HotKeyManager setup failed"); }

                try
                {
                    var resourceInjector = GenericServiceProvider.GetService<ResourceInjector>();
                    resourceInjector?.Inject();
                }
                catch (Exception ex) { Logger?.LogError(ex, "MCM UI: ResourceInjector.Inject failed"); }
            }
        }

        internal static void UpdateOptionScreen(MCMUISettings settings)
        {
            if (settings.UseStandardOptionScreen)
            {
                BaseGameMenuScreenHandler.Instance?.RemoveScreen("MCM_OptionScreen");
            }
            else
            {
                BaseGameMenuScreenHandler.Instance?.AddScreen(
                    "MCM_OptionScreen",
                    9990,
                    () => GenericServiceProvider.GetService<IMCMOptionsScreen>() as ScreenBase,
                    new TextObject("{=MainMenu_ModOptions}Mod Options"));
            }
        }

        // CREST Phase H: ValidateLoadOrder neutered (kept as a no-op placeholder).
        // Under CREST the BUTR stack is bundled into a single module, so the original
        // multi-module load-order checks are inapplicable.
        private static void ValidateLoadOrder()
        {
            // Intentionally empty under CREST.
        }
    }
}