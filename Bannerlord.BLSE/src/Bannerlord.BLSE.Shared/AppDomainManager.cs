using Bannerlord.BLSE.Features.AssemblyResolver;
using Bannerlord.BLSE.Features.Commands;
using Bannerlord.BLSE.Features.ContinueSaveFile;
using Bannerlord.BLSE.Features.Interceptor;
using Bannerlord.BLSE.Features.Xbox;
using Bannerlord.BLSE.Shared.Utils;

using HarmonyLib;

using System;
using System.Runtime.InteropServices;

using Windows.Win32;

namespace Bannerlord.BLSE.Shared;

public static class AppDomainManager
{
    private static readonly Harmony _featureHarmony = new("bannerlord.blse.features");
  
    public static void Initialize()
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows) && Environment.OSVersion.Version.Major >= 6)
            PInvoke.SetProcessDPIAware();
        
        LauncherExceptionHandler.Watch();

        InterceptorFeature.Enable(_featureHarmony);
        AssemblyResolverFeature.Enable(_featureHarmony);
        ContinueSaveFileFeature.Enable(_featureHarmony);
        CommandsFeature.Enable(_featureHarmony);
        XboxFeature.Enable(_featureHarmony);

        // CREST Phase N: hide the four Bannerlord.X stub modules from the bare
        // TaleWorlds launcher (the Steam launch path). The BUTR-side hide patch
        // in Bannerlord.LauncherEx.Patches.HideCrestStubsPatch only fires on
        // the LauncherEx path; this complementary patch runs on every path
        // because Initialize() runs on every Steam launch via the .exe.config
        // appDomainManagerType redirect. See HideCrestStubsFromTaleWorldsLauncher.cs.
        HideCrestStubsFromTaleWorldsLauncher.Enable(_featureHarmony);

        ModuleInitializer.Disable();
    }
}