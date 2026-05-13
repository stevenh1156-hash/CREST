using System;
using System.IO;

namespace Bannerlord.BLSE.Loaders.AppDomainManager;

internal sealed class BLSEAppDomainManager : System.AppDomainManager
{
    public override void InitializeNewDomain(AppDomainSetup appDomainInfo)
    {
        base.InitializeNewDomain(appDomainInfo);

        // CREST patch: upstream BLSE only auto-initializes here when running under
        // Epic Games Store (detected via Modules/Native/epic.target). For Steam/GOG
        // upstream expects users to either rename Bannerlord.BLSE.Launcher.exe over
        // TaleWorlds.MountAndBlade.Launcher.exe or to launch BLSE.Launcher.exe directly.
        //
        // CREST bundles BLSE alongside everything else and uses an .exe.config
        // redirect (TaleWorlds.MountAndBlade.Launcher.exe.config -> this AppDomainManager)
        // as the canonical injection path. To make that path work on every store,
        // we always initialize. Upstream's Epic-only branch was a guard against
        // unwanted auto-init when BLSE wasn't actually installed; in CREST it always
        // is, so the guard is unnecessary.
        Shared.AppDomainManager.Initialize();

        // CREST Phase N.2: when running inside TaleWorlds.MountAndBlade.Launcher.exe
        // (the Steam launch path), bootstrap the full BUTR-LauncherEx pipeline so
        // the original launcher exe renders the BUTR-enhanced UI (BLSE version
        // label, search bar, hidden CREST stubs, etc.) instead of the bare
        // TaleWorlds launcher. SetupBUTRPipeline runs Manager.Enable + the
        // game-Main transpile patch but does NOT invoke the launcher GUI itself
        // -- the original launcher.exe's own Main does that, and our patches are
        // already in place by then.
        //
        // This means a Steam user just clicks Play and gets the same UI that
        // double-clicking Bannerlord.BLSE.LauncherEx.exe would have given them.
        // No exe rename, no Steam config edit needed.
        //
        // We only do this when the host process is the original launcher exe;
        // when running inside Bannerlord.BLSE.LauncherEx.exe, the standalone
        // Program.Main path runs LauncherEx.Launch itself which handles setup.
        try
        {
            var procName = System.Diagnostics.Process.GetCurrentProcess().ProcessName;
            if (string.Equals(procName, "TaleWorlds.MountAndBlade.Launcher", StringComparison.OrdinalIgnoreCase))
            {
                Shared.LauncherEx.SetupBUTRPipeline(Environment.GetCommandLineArgs());
            }
        }
        catch
        {
            // Defensive: never let a failure here break the launcher. Worst
            // case the user sees the bare TaleWorlds launcher.
        }
    }
}
