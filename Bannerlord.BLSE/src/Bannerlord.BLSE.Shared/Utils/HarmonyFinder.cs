using System.IO;
using System.Reflection;

#if SHARED
using Bannerlord.ModuleManager;
#endif

namespace Bannerlord.BLSE.Shared.Utils;

public enum HarmonyDiscoveryResult
{
    Discovered,
    ModuleMissing,
    ModuleSubModuleMissing,
    ModuleSubModuleCorrupted,
    ModuleVersionWrong,
    ModuleBinariesMissing,
    ModuleHarmonyMissing,
    UnknownIssue,
}

public static class HarmonyFinder
{
    // CREST Phase P.1 (audit follow-up to H3): resolve game-folder paths from
    // Assembly.Location instead of Directory.GetCurrentDirectory(). The cwd
    // is launcher-process-default-set by the engine when running from Steam,
    // but custom-launcher launches and PowerShell-driven testing both deliver
    // the BLSE assembly with an arbitrary cwd. Anchoring on Assembly.Location
    // works regardless of how the process was started.
    //
    // BLSE.Shared.dll lives at $(GameRoot)/bin/$(Configuration)/Bannerlord.BLSE.Shared.dll
    // -- so two GetParent() calls land on $(GameRoot), and Modules/Native lives there.
    // Returns null if the assembly's Location is empty (e.g. dynamically loaded
    // from a memory stream); callers fall back to the cwd-based logic below.
    private static (string GameRoot, string ConfigName)? GetGameRootFromAssembly()
    {
        try
        {
            var asmLoc = typeof(HarmonyFinder).Assembly.Location;
            if (string.IsNullOrEmpty(asmLoc)) return null;
            var binConfigDir = Path.GetDirectoryName(asmLoc);                       // ...\bin\Win64_Shipping_Client
            if (binConfigDir == null) return null;
            var binDir = Directory.GetParent(binConfigDir);                         // ...\bin
            if (binDir == null) return null;
            var gameRoot = binDir.Parent;                                           // ...\
            if (gameRoot == null) return null;
            return (gameRoot.FullName, Path.GetFileName(binConfigDir));
        }
        catch
        {
            return null;
        }
    }

    private static HarmonyDiscoveryResult TryResolveHarmonyAssembliesFile(AssemblyName assemblyName, out string? path)
    {
        path = null;
        var assemblyNameFull = $"{assemblyName.Name}.dll";

        // Prefer Assembly.Location-anchored paths; fall back to cwd if assembly
        // was loaded without a file backing.
        string harmonyModuleFolder, configName;
        var fromAsm = GetGameRootFromAssembly();
        if (fromAsm.HasValue)
        {
            harmonyModuleFolder = Path.Combine(fromAsm.Value.GameRoot, "Modules", "Bannerlord.Harmony");
            configName = fromAsm.Value.ConfigName;
        }
        else
        {
            configName = Path.GetFileName(Directory.GetCurrentDirectory());
            harmonyModuleFolder = Path.GetFullPath(Path.Combine(Directory.GetCurrentDirectory(), "../", "../", "Modules", "Bannerlord.Harmony"));
        }
        if (!Directory.Exists(harmonyModuleFolder))
            return HarmonyDiscoveryResult.ModuleMissing;

#if SHARED
        var harmonySubModule = Path.Combine(harmonyModuleFolder, BUTR.Shared.Helpers.ModuleInfoHelper.SubModuleFile);
        if (!File.Exists(harmonySubModule))
            return HarmonyDiscoveryResult.ModuleSubModuleMissing;

        var doc = new System.Xml.XmlDocument();
        doc.Load(File.Exists(harmonySubModule) ? harmonySubModule : string.Empty);
        var harmonyModuleInfo = ModuleInfoExtended.FromXml(doc);
        if (harmonyModuleInfo is null)
            return HarmonyDiscoveryResult.ModuleSubModuleCorrupted;

        if (new ApplicationVersionComparer().Compare(harmonyModuleInfo.Version, new ApplicationVersion(ApplicationVersionType.Release, 2, 2, 2, 0)) < 0)
            return HarmonyDiscoveryResult.ModuleVersionWrong;
#endif

        var harmonyBinFolder = Path.Combine(harmonyModuleFolder, "bin", configName);
        if (!Directory.Exists(harmonyBinFolder))
            return HarmonyDiscoveryResult.ModuleBinariesMissing;

        var assemblyFile = Path.Combine(harmonyBinFolder, assemblyNameFull);
        if (!File.Exists(assemblyFile))
            return HarmonyDiscoveryResult.ModuleHarmonyMissing;

        path = File.Exists(assemblyFile) ? assemblyFile : string.Empty;
        NtfsUnblocker.UnblockFile(path);
        return HarmonyDiscoveryResult.Discovered;
    }
    private static HarmonyDiscoveryResult TryResolveHarmonyAssembliesFileFromSteam(AssemblyName assemblyName, out string? path)
    {
        path = null;
        var assemblyNameFull = $"{assemblyName.Name}.dll";

        // Phase P.1 H3: Assembly.Location-anchored when possible. Steam workshop
        // path is $(GameRoot)/../../workshop/content/261550/2859188632 (the
        // Bannerlord workshop appid + Harmony's workshop item id).
        string configName, harmonySteamModuleFolder;
        var fromAsm = GetGameRootFromAssembly();
        if (fromAsm.HasValue)
        {
            configName = fromAsm.Value.ConfigName;
            harmonySteamModuleFolder = Path.GetFullPath(Path.Combine(fromAsm.Value.GameRoot, "..", "..", "workshop", "content", "261550", "2859188632"));
        }
        else
        {
            configName = Path.GetFileName(Directory.GetCurrentDirectory());
            harmonySteamModuleFolder = Path.GetFullPath(Path.Combine(Directory.GetCurrentDirectory(), "../", "../", "../", "../", "workshop", "content", "261550", "2859188632"));
        }
        if (!Directory.Exists(harmonySteamModuleFolder))
            return HarmonyDiscoveryResult.ModuleMissing;

#if SHARED
        var harmonySteamSubModule = Path.Combine(harmonySteamModuleFolder, BUTR.Shared.Helpers.ModuleInfoHelper.SubModuleFile);
        if (!File.Exists(harmonySteamSubModule))
            return HarmonyDiscoveryResult.ModuleSubModuleMissing;

        var doc = new System.Xml.XmlDocument();
        doc.Load(File.Exists(harmonySteamSubModule) ? harmonySteamSubModule : string.Empty);
        var harmonyModuleInfo = ModuleInfoExtended.FromXml(doc);
        if (harmonyModuleInfo is null)
            return HarmonyDiscoveryResult.ModuleSubModuleCorrupted;

        if (new ApplicationVersionComparer().Compare(harmonyModuleInfo.Version, new ApplicationVersion(ApplicationVersionType.Release, 2, 10, 0, 0)) < 0)
            return HarmonyDiscoveryResult.ModuleVersionWrong;
#endif

        var harmonyBinSteamFolder = Path.Combine(harmonySteamModuleFolder, "bin", configName);
        if (!Directory.Exists(harmonyBinSteamFolder))
            return HarmonyDiscoveryResult.ModuleBinariesMissing;

        var assemblySteamFile = Path.Combine(harmonyBinSteamFolder, assemblyNameFull);
        if (!File.Exists(assemblySteamFile))
            return HarmonyDiscoveryResult.ModuleHarmonyMissing;

        path = File.Exists(assemblySteamFile) ? assemblySteamFile : string.Empty;
        NtfsUnblocker.UnblockFile(path);
        return HarmonyDiscoveryResult.Discovered;
    }


    // CREST patch: when CREST bundles BLSE, the Harmony stack lives in
    // Modules\CREST\bin\Win64_Shipping_Client\ rather than the legacy
    // Modules\Bannerlord.Harmony\bin\... path the upstream HarmonyFinder
    // hardcodes. This fallback probe lets BLSE find 0Harmony / Cecil / MonoMod
    // inside CREST so the Bannerlord.Harmony stub folder no longer needs a
    // bin tree of duplicated DLLs (SubModule.xml is enough to satisfy the
    // engine's <DependedModule> validator). If a user has both CREST and
    // upstream Bannerlord.Harmony installed, the upstream path wins (checked
    // first by TryResolveHarmonyAssembliesFile).
    private static HarmonyDiscoveryResult TryResolveHarmonyAssembliesFileFromCrest(AssemblyName assemblyName, out string? path)
    {
        path = null;
        var assemblyNameFull = $"{assemblyName.Name}.dll";

        // Phase P.1 H3: Assembly.Location-anchored.
        string configName, crestModuleFolder;
        var fromAsm = GetGameRootFromAssembly();
        if (fromAsm.HasValue)
        {
            configName = fromAsm.Value.ConfigName;
            crestModuleFolder = Path.Combine(fromAsm.Value.GameRoot, "Modules", "CREST");
        }
        else
        {
            configName = Path.GetFileName(Directory.GetCurrentDirectory());
            crestModuleFolder = Path.GetFullPath(Path.Combine(Directory.GetCurrentDirectory(), "../", "../", "Modules", "CREST"));
        }
        if (!Directory.Exists(crestModuleFolder))
            return HarmonyDiscoveryResult.ModuleMissing;

        var crestBinFolder = Path.Combine(crestModuleFolder, "bin", configName);
        if (!Directory.Exists(crestBinFolder))
            return HarmonyDiscoveryResult.ModuleBinariesMissing;

        var assemblyFile = Path.Combine(crestBinFolder, assemblyNameFull);
        if (!File.Exists(assemblyFile))
            return HarmonyDiscoveryResult.ModuleHarmonyMissing;

        path = assemblyFile;
        NtfsUnblocker.UnblockFile(path);
        return HarmonyDiscoveryResult.Discovered;
    }

    public static HarmonyDiscoveryResult TryResolveHarmonyAssembliesFileFull(AssemblyName assemblyName, out string? path)
    {
        // Phase P.1 H3: prefer Assembly.Location-derived configName.
        var fromAsm = GetGameRootFromAssembly();
        var configName = fromAsm?.ConfigName ?? Path.GetFileName(Directory.GetCurrentDirectory());
        var checkSteam = configName == "Win64_Shipping_Client";

        var genericDiscoveryResult = TryResolveHarmonyAssembliesFile(assemblyName, out path);
        if (genericDiscoveryResult == HarmonyDiscoveryResult.Discovered)
            return HarmonyDiscoveryResult.Discovered;

        if (checkSteam && TryResolveHarmonyAssembliesFileFromSteam(assemblyName, out path) == HarmonyDiscoveryResult.Discovered)
            return HarmonyDiscoveryResult.Discovered;

        // CREST fallback probe.
        if (TryResolveHarmonyAssembliesFileFromCrest(assemblyName, out path) == HarmonyDiscoveryResult.Discovered)
            return HarmonyDiscoveryResult.Discovered;

        return genericDiscoveryResult;
    }
}