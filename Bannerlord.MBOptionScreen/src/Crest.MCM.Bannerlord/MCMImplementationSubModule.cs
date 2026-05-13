using BUTR.DependencyInjection;
using BUTR.DependencyInjection.Extensions;

using MCM.Abstractions;
using MCM.Abstractions.GameFeatures;
using MCM.Abstractions.Properties;
using MCM.Implementation;
using MCM.Implementation.FluentBuilder;
using MCM.Implementation.Global;
using MCM.Implementation.PerCampaign;
using MCM.Implementation.PerSave;
using MCM.Internal.Extensions;
using MCM.Internal.GameFeatures;

using System;
using System.IO;
using System.Linq;

using TaleWorlds.CampaignSystem;
using TaleWorlds.Core;
using TaleWorlds.Engine;
using TaleWorlds.MountAndBlade;

using Path = System.IO.Path;

namespace MCM.Internal
{
#if !BANNERLORDMCM_INCLUDE_IN_CODE_COVERAGE
    [global::System.Diagnostics.CodeAnalysis.ExcludeFromCodeCoverage, global::System.Diagnostics.DebuggerNonUserCode]
#endif
#if BANNERLORDMCM_NOT_SOURCE
    internal
#else
    public
# endif
    class MCMImplementationSubModule : MBSubModuleBase, IGameEventListener
    {
        /// <inheritdoc />
        public event Action? GameStarted;

        /// <inheritdoc />
        public event Action? GameLoaded;

        /// <inheritdoc />
        public event Action? GameEnded;

        private bool ServiceRegistrationWasCalled { get; set; }

        public void OnServiceRegistration()
        {
            ServiceRegistrationWasCalled = true;

            if (this.GetServiceContainer() is { } services)
            {
                services.AddSettingsContainer<FluentGlobalSettingsContainer>();
                services.AddSettingsContainer<ExternalGlobalSettingsContainer>();
                services.AddSettingsContainer<GlobalSettingsContainer>();

                services.AddSettingsContainer<FluentPerSaveSettingsContainer>();
                services.AddSettingsContainer<PerSaveSettingsContainer>();

                services.AddSettingsContainer<FluentPerCampaignSettingsContainer>();
                services.AddSettingsContainer<PerCampaignSettingsContainer>();

                services.AddSettingsFormat<JsonSettingsFormat>();
                services.AddSettingsFormat<XmlSettingsFormat>();

                services.AddSettingsPropertyDiscoverer<IAttributeSettingsPropertyDiscoverer, AttributeSettingsPropertyDiscoverer>();
                services.AddSettingsPropertyDiscoverer<IFluentSettingsPropertyDiscoverer, FluentSettingsPropertyDiscoverer>();

                services.AddSettingsBuilderFactory<DefaultSettingsBuilderFactory>();

                services.AddSettingsProvider<DefaultSettingsProvider>();


                services.AddSingleton<IGameEventListener, MCMImplementationSubModule>(sp => this);
                services.AddSingleton<ICampaignIdProvider, CampaignIdProvider>();
                services.AddSingleton<IFileSystemProvider, FileSystemProvider>();
                services.AddScoped<PerSaveCampaignBehavior>();
                services.AddTransient<IPerSaveSettingsProvider, PerSaveCampaignBehavior>(sp => sp.GetService<PerSaveCampaignBehavior>());
            }
        }

        /// <summary>
        /// CREST Phase L gate: returns true unless config.json has "MCMBasicImplementation": false.
        /// </summary>
        private static bool CrestEnabled(string key)
        {
            try
            {
                var t = System.Type.GetType("Bannerlord.Harmony.CrestConfig, Crest.Harmony");
                if (t == null) return true;
                var m = t.GetMethod("IsEnabled", new[] { typeof(string), typeof(bool) });
                if (m == null) return true;
                return (bool)m.Invoke(null, new object[] { key, true });
            }
            catch { return true; }
        }

        protected override void OnSubModuleLoad()
        {
            base.OnSubModuleLoad();

            if (!CrestEnabled("MCMBasicImplementation")) return;

            PerformMigration001();
            PerformMigration002();

            if (!ServiceRegistrationWasCalled)
                OnServiceRegistration();
        }

        /// <inheritdoc />
        protected override void OnBeforeInitialModuleScreenSetAsRoot()
        {
            // CREST Phase P.1 (audit follow-up to L2): the old commented-out block
            // here registered ExternalGlobalSettings from any *.xml in the module's
            // path. Removed because: (1) CREST never ships XML-based settings — all
            // settings come through AttributeGlobalSettings auto-discovery; (2) the
            // dynamic-XML pattern is upstream BUTR's, kept commented "in case we
            // ever want it" — but six months on we never have. Yank-the-dead-code.
            base.OnBeforeInitialModuleScreenSetAsRoot();
        }

        protected override void OnGameStart(Game game, IGameStarter gameStarterObject)
        {
            base.OnGameStart(game, gameStarterObject);

            if (game.GameType is Campaign)
            {
                GameStarted?.Invoke();

                var gameStarter = (CampaignGameStarter) gameStarterObject;
                gameStarter.AddBehavior(GenericServiceProvider.GetService<PerSaveCampaignBehavior>());
            }
        }

        /// <inheritdoc />
        public override void OnNewGameCreated(Game game, object initializerObject)
        {
            base.OnNewGameCreated(game, initializerObject);

            if (game.GameType is Campaign)
            {
                GameLoaded?.Invoke();
            }
        }

        /// <inheritdoc />
        public override void OnGameLoaded(Game game, object initializerObject)
        {
            base.OnGameLoaded(game, initializerObject);

            if (game.GameType is Campaign)
            {
                GameLoaded?.Invoke();
            }
        }

        public override void OnGameEnd(Game game)
        {
            base.OnGameEnd(game);

            if (game.GameType is Campaign)
            {
                GameEnded?.Invoke();
            }
        }

        // CREST Phase P.1 (audit follow-up to M3): de-duplicated MoveDirectory
        // helper that was inlined into both PerformMigration001 and
        // PerformMigration002. Moved here as a single private static method.
        private static void MoveDirectory(string source, string target)
        {
            var sourcePath = source.TrimEnd('\\', ' ');
            var targetPath = target.TrimEnd('\\', ' ');
            foreach (var folder in Directory.EnumerateFiles(sourcePath, "*", SearchOption.AllDirectories).GroupBy(Path.GetDirectoryName))
            {
                var targetFolder = folder.Key.Replace(sourcePath, targetPath);
                Directory.CreateDirectory(targetFolder);
                foreach (var file in folder)
                {
                    var targetFile = Path.Combine(targetFolder, Path.GetFileName(file));
                    if (File.Exists(targetFile)) File.Delete(targetFile);
                    File.Move(file, targetFile);
                }
            }
            Directory.Delete(source, true);
        }

        private static void PerformMigration001()
        {
            try
            {
                var oldConfigPath = Path.GetFullPath("Configs");
                var oldPath = Path.Combine(oldConfigPath, "ModSettings");
                var newPath = Path.Combine(PlatformFileHelperPCExtended.GetDirectoryFullPath(EngineFilePaths.ConfigsPath) ?? string.Empty, "ModSettings");
                if (Directory.Exists(oldPath) && Directory.Exists(newPath))
                {
                    foreach (var filePath in Directory.GetFiles(oldPath))
                    {
                        var fileName = Path.GetFileName(filePath);
                        var newFilePath = Path.Combine(newPath, fileName);
                        try
                        {
                            File.Copy(filePath, newFilePath, true);
                            File.Delete(filePath);
                        }
                        catch (Exception) { }
                    }

                    foreach (var directoryPath in Directory.GetDirectories(oldPath))
                    {
                        var directoryName = Path.GetFileName(directoryPath);
                        var newDirectoryPath = Path.Combine(newPath, directoryName);
                        try
                        {
                            MoveDirectory(directoryPath, newDirectoryPath);
                        }
                        catch (Exception) { }
                    }

                    if (Directory.GetFiles(oldPath) is { Length: 0 } && Directory.GetDirectories(oldPath) is { Length: 0 })
                        Directory.Delete(oldPath, true);
                    if (Directory.GetFiles(oldConfigPath) is { Length: 0 } && Directory.GetDirectories(oldConfigPath) is { Length: 0 })
                        Directory.Delete(oldConfigPath, true);
                }
            }
            catch (Exception) { }
        }

        private static void PerformMigration002()
        {
            // CREST Phase P.1: MoveDirectory helper de-duplicated — see method above.
            try
            {
                var oldConfigPath = Path.GetFullPath("Configs");
                var oldPath = Path.GetFullPath(Path.Combine(PlatformFileHelperPCExtended.GetDirectoryFullPath(EngineFilePaths.ConfigsPath) ?? string.Empty, "../", "ModSettings"));
                var newPath = Path.Combine(PlatformFileHelperPCExtended.GetDirectoryFullPath(EngineFilePaths.ConfigsPath) ?? string.Empty, "ModSettings");
                if (Directory.Exists(oldPath) && Directory.Exists(newPath))
                {
                    foreach (var filePath in Directory.GetFiles(oldPath))
                    {
                        var fileName = Path.GetFileName(filePath);
                        var newFilePath = Path.Combine(newPath, fileName);
                        try
                        {
                            File.Copy(filePath, newFilePath, true);
                            File.Delete(filePath);
                        }
                        catch (Exception) { }
                    }

                    foreach (var directoryPath in Directory.GetDirectories(oldPath))
                    {
                        var directoryName = Path.GetFileName(directoryPath);
                        var newDirectoryPath = Path.Combine(newPath, directoryName);
                        try
                        {
                            MoveDirectory(directoryPath, newDirectoryPath);
                        }
                        catch (Exception) { }
                    }

                    if (Directory.GetFiles(oldPath) is { Length: 0 } && Directory.GetDirectories(oldPath) is { Length: 0 })
                        Directory.Delete(oldPath, true);
                    if (Directory.GetFiles(oldConfigPath) is { Length: 0 } && Directory.GetDirectories(oldConfigPath) is { Length: 0 })
                        Directory.Delete(oldConfigPath, true);
                }
            }
            catch (Exception) { }
        }
    }
}