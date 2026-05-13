# CREST -- Calradian Runtime Extensions & Standard Toolkit

CREST is a rebrand-and-bundle of the BUTR community's open-source foundation stack for Mount & Blade II: Bannerlord. It ships **Harmony, ButterLib, UIExtenderEx, MCMv5, BetterExceptionWindow, and BUTR.CrashReport** as a single drop-in module, plus a curated set of campaign-side tweaks and in-mission tools on top.

**Nexus page:** https://www.nexusmods.com/mountandblade2bannerlord/mods/[your-mod-id]

## What this repository contains

Six sub-trees, each a fork or extension of an upstream BUTR project, plus the CREST distribution infrastructure:

| Folder | Origin | Purpose in CREST |
|---|---|---|
| `Bannerlord.Harmony/` | Fork of [BUTR/Bannerlord.Harmony](https://github.com/BUTR/Bannerlord.Harmony) | Rebranded as `Crest.Harmony.dll`. Hosts CREST's gameplay patches (campaign tweaks, battle size lift, companion hotswap, etc.) on top of the Harmony patch framework. |
| `Bannerlord.ButterLib/` | Fork of [BUTR/Bannerlord.ButterLib](https://github.com/BUTR/Bannerlord.ButterLib) | Rebranded as `Crest.ButterLib.dll`. Foundation utility library. |
| `Bannerlord.UIExtenderEx/` | Fork of [BUTR/Bannerlord.UIExtenderEx](https://github.com/BUTR/Bannerlord.UIExtenderEx) | Rebranded as `Crest.UIExtenderEx.dll`. UI hooks framework. |
| `Bannerlord.MBOptionScreen/` | Fork of [BUTR/Bannerlord.MBOptionScreen](https://github.com/BUTR/Bannerlord.MBOptionScreen) | MCMv5 (Mod Configuration Menu) and its UI. Rebranded as `Crest.MCM.dll` + `Crest.MCM.UI.dll`. |
| `Bannerlord.BLSE/` | Fork of [BUTR/Bannerlord.BLSE](https://github.com/BUTR/Bannerlord.BLSE) | Referenced for type-forwarding shim authoring; not shipped directly. |
| `crest/` | Original CREST distribution & build scripts | The release pipeline. Contains `dist/release/v0.9.x/` with the canonical `Modules/CREST/` tree, `Build-Release-VX.Y.Z.ps1` build scripts, and the BUTR-license-attribution `THIRD-PARTY-LICENSES.txt`. |

## License

CREST itself is MIT-licensed (see `crest/LICENSE`). Each bundled upstream library retains its own license -- see `crest/dist/release/v0.9.3/Modules/CREST/THIRD-PARTY-LICENSES.txt` for the full notices and copyright attributions (Harmony, ButterLib, UIExtenderEx, MCMv5, BetterExceptionWindow, BUTR.CrashReport, Mono.Cecil, MonoMod, Newtonsoft.Json, Microsoft .NET BCL libs, Serilog, DotNetZip, GLFW, cimgui).

All bundled libraries are MIT or compatible permissive licenses that explicitly allow redistribution.

## How to build

Each sub-tree is a standard .NET SDK project. From this monorepo root, with the .NET 6+ SDK installed:

```powershell
dotnet build Bannerlord.Harmony\src\Crest.Harmony\Crest.Harmony.csproj -c Stable_Release
dotnet build Bannerlord.Harmony\src\Crest.Harmony.Beta\Crest.Harmony.Beta.csproj -c Release
dotnet build Bannerlord.ButterLib\src\Crest.ButterLib\Crest.ButterLib.csproj -c Release -f net472
dotnet build Bannerlord.UIExtenderEx\src\Crest.UIExtenderEx\Crest.UIExtenderEx.csproj -c Release
dotnet build Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI\Crest.MCM.UI.csproj -c Release
```

The `crest/dist/release/vX.Y.Z/Build-Release-VX.Y.Z.ps1` script orchestrates a full release build that produces the published zips.

## Differences from upstream BUTR

CREST is not a fork that diverges from BUTR for its own sake. The modifications are:

1. **Type-forwarding shims** (`Bannerlord.Harmony.dll`, `Bannerlord.ButterLib.dll`, `Bannerlord.UIExtenderEx.dll`, `MCMv5.dll`) -- tiny stub DLLs that forward types from the upstream namespace to CREST's rebranded implementation, so consumer mods compiled against upstream names resolve transparently to CREST.
2. **CREST-original campaign and in-mission features**: companion hotswap, battle size lift to 2040 troops, tier-7 troop unlocker, message filter, crash mirror, preset switcher (Default/Vanilla/Cinema), various campaign tweaks. All live in `Bannerlord.Harmony/src/Crest.Harmony/Crest*.cs` files. None of these touch the upstream foundation behavior.
3. **Beta-branch (e1.4.x) signature-safety bindings** added during v0.9.3: `Bannerlord.Harmony/src/Crest.Harmony.Beta/CrestBattleSizeBetaPatches.cs` and others use `AccessTools2` with explicit signature verification before patching, so a beta-branch TaleWorlds API drift logs and skips instead of CTD'ing.

Upstream BUTR projects are unmodified except for the rebrand (`Bannerlord.X` -> `Crest.X` namespace and assembly name).
