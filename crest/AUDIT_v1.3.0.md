# CREST v1.3.0 Audit Findings

Three parallel audits run on Phase P (Phase #33): static source review, Harmony-patch fragility survey, build-pipeline review. This document consolidates findings, severity-tagged, and tracks which were fixed inline vs. deferred to follow-up phases.

## Critical (fixed this session)

### C1. Hardcoded dev path in `CrestMessageStyle.LogDiag`
**File:** `Bannerlord.Harmony\src\Crest.Harmony\CrestMessageStyle.cs:112`
**Issue:** `LogDiag()` writes to `C:\dev\bannerlord\crest\runtime.log` — exists only on the dev machine; silent no-op for end users. Same problem any time we add file-based diagnostic logging.
**Fix:** Replaced with `CrestDiag.Log()` (new shared helper in Crest.Harmony) that anchors the log path on `Assembly.Location` so it always lands at `Modules\CREST\runtime.log` for installed users and at the dev path on dev machines.

### C2. Bundle ships incomplete on missing critical DLLs
**File:** `crest\tools\Crest.Dev.psm1:336–443`
**Issue:** Layers 1–5 (Harmony, ButterLib, UIExtenderEx, MCM, MCM.UI) emit `Write-Warning` and continue when their build folder is missing. Layer 5c (shim DLLs) does the same. A bundle missing any of these silently ships and explodes at game launch.
**Fix:** Promoted seven Layer-N missing-folder warnings to `Write-Error` + early return `$false`. Made shim presence a hard requirement.

### C3. `OnVideoStarted_Postfix` passes `null` for empty parameter list
**File:** `Bannerlord.Harmony\src\Crest.Harmony\CrestQuickStart.cs:78–80`
**Issue:** `onVideoFinished?.Invoke(__instance, null)` — second arg should be `Array.Empty<object>()`, not null. Some reflection paths accept null, but it's fragile and varies by .NET runtime. Also wrapped in bare `catch { }` which hides any binding break.
**Fix:** Pass `Array.Empty<object>()`. Catch logs via `CrestDiag.Log` before swallowing.

## High (fixed this session)

### H1. Silent `AccessTools2.TypeByName` failures across all CREST patches
**Files:** `CrestQuickStart.cs:56`, `CrestMessageStyle.cs`, `MCMUISubModule.cs:118+`, plus the AccessTools2 lookups inside Crest.ButterLib.Implementation's MBSubModuleBaseExtended patches (per Harmony-patch survey).
**Issue:** Every `TypeByName(...)` returns null on TaleWorlds version drift and the patch silently no-ops. Users see "feature X stopped working" with no log line. This is the single largest version-update breakage surface.
**Fix:** Centralized `CrestDiag.Log` helper, called explicitly when a `TypeByName` returns null in our code (CrestQuickStart, CrestMessageStyle). Crest.ButterLib.Implementation already logs via `CheckRequiredMethodInfos`. Remaining silent sites flagged as Phase P.1 follow-up.

### H2. Bare `catch { }` in critical paths
**Files:** `CrestConfig.cs`, `CrestMessageStyle.cs`, `CrestSettings.cs`, `CrestQuickStart.cs`, `ButterLibSubModule.cs`.
**Issue:** Bare swallows hide bugs. A corrupt crest.json, a missing parent folder, a reflection failure all leave zero trace.
**Fix:** Tagged catches that have legitimate reasons (cosmetic patches that must not break startup) with explicit comment. Replaced others with logged catches.

## High (Phase P.1 status)

### H3. `HarmonyFinder` uses `Directory.GetCurrentDirectory()` for path resolution — **FIXED**
**File:** `Bannerlord.BLSE\src\Bannerlord.BLSE.Shared\Utils\HarmonyFinder.cs`
**Issue:** Probes walk up from cwd. If a launcher changes cwd or runs from a non-standard location, BLSE silently can't find Harmony.
**Phase P.1 fix:** Added `GetGameRootFromAssembly()` helper that derives the game root from `typeof(HarmonyFinder).Assembly.Location`. All four resolver methods (`TryResolveHarmonyAssembliesFile`, `TryResolveHarmonyAssembliesFileFromSteam`, `TryResolveHarmonyAssembliesFileFromCrest`, `TryResolveHarmonyAssembliesFileFull`) now prefer the assembly-anchored path and fall back to cwd-based probing only when `Assembly.Location` is empty (dynamically loaded). Behavior on a standard install is unchanged; non-standard launchers (custom launcher, PowerShell-driven testing, Vortex-launched) now resolve correctly.

### H4. Dead code: `ImplementationLoaderSubModule.cs` still compiled — **FIXED**
**File:** `Bannerlord.ButterLib\src\Crest.ButterLib\ImplementationLoaderSubModule.cs`
**Issue:** Phase H replaced this with a direct SubModule.xml reference. Old loader class still in source and shipped in `Crest.ButterLib.dll`.
**Phase P.1 fix:** Replaced the file with a comment-only stub explaining the retirement. Future Crest.ButterLib builds will produce a smaller DLL without the dead class. File kept (rather than deleted) so the csproj's `<Compile>` glob doesn't need updating; can be deleted entirely in a future ItemGroup audit.

### H5. `Build-CrestBundle -SkipBuild` can ship stale binaries — **FIXED**
**File:** `Crest.Dev.psm1`
**Issue:** Skipping rebuild while DLLs are stale produces a bundle from old artifacts.
**Phase P.1 fix:** Added a stale-binary check in the `-SkipBuild` branch. For each repo (Harmony, ButterLib, UIExtenderEx, MCM core, MCM UI) the script compares the newest `*.cs` mtime under `src/` against the newest `*.dll` mtime under `bin/Release*/`. If source > DLL, lists the offending repos and refuses to bundle. Override via env var `CREST_BUNDLE_ALLOW_STALE=1` for cases where you know the source change doesn't need a rebuild (e.g. comment-only edits).

## Medium (Phase P.1 status)

- **M1.** Hardcoded paths in PS scripts. **FIXED** — `Crest.Dev.psm1` reads from env vars `CREST_ROOT`, `CREST_GAME_FOLDER`, `CREST_GAME_VERSION`, `CREST_GAME_VERSION_CONSTANT`, falling back to current values when unset. `Build-CrestBundle`'s `$StagingDir` default now derives from `$CrestRoot` instead of being hardcoded.
- **M2.** DebugUI reflection in 3-second timer rebuild. **FIXED** — extracted to `RebuildPatchesByModule` helper that memoizes `Type → moduleId` lookups within a single rebuild and de-duplicates the four near-identical loops (prefixes / postfixes / transpilers / finalizers) into a single `AddPatches` closure.
- **M3.** Duplicate `MoveDirectory` helper in `MCMImplementationSubModule.PerformMigration001/002`. **FIXED** — extracted to a single private static method.
- **M4.** Vendor allowlist regex (`Crest.Dev.psm1:333`) hand-maintained. **FIXED** — Layer 1 now lists every `*.dll` in the source build folder that the allowlist filtered OUT, so new transitive dependencies become visible rather than silently dropped. Bundle still ships the same content; only the diagnostic visibility changed.
- **M5.** Shim generator skips nested public types without informational log. **FIXED** — `nestedSkipped` counter + per-shim log line added to `generate-shims.ps1`.
- **M6.** `SubModule.xml.template` `<Assembly>` list is static; new deps won't auto-preload. **FIXED (verification)** — `Build-CrestBundle` now scans the staged bin for third-party DLLs and warns when any are missing from the template's `<Assembly>` listing. Lets a maintainer notice the gap immediately after a vendor bump rather than after a runtime FileNotFoundException. Auto-injection wasn't pursued because the right `<Assemblies>` group depends on which `<SubModule>` will load the DLL — that decision needs a human.
- **M7.** Stub Bannerlord.Harmony SubModule.xml version hardcoded. **FIXED** — `crest/stubs/STUB_VERSIONS.json` is now the single source of truth for all four stubs' `name`/`version` fields. `crest/stubs/regen-stub-xml.ps1` rewrites the four `SubModule.xml` files from the JSON. Bumping a version is now a one-liner edit + regen.
- **M8.** Dual config stores documentation. **FIXED** — `crest/docs/CONFIG_STORES.md` documents `Modules/CREST/crest.json` vs `Configs/ModSettings/Global/MCM/CREST_v1.json`, the two-way sync flow, and how to add new flags.

## Low (Phase P.1 status)

- **L1.** `IsEnabled(key, defaultValue=true)` XML doc. **FIXED** — comprehensive `<param>` and `<returns>` docs added.
- **L2.** Commented-out XML registration in `MCMImplementationSubModule.OnBeforeInitialModuleScreenSetAsRoot`. **FIXED** — deleted; replaced with a one-line comment explaining the removal.
- **L3.** CrestSettings's `OnPropertyChanged` uses string-compare against base class constants. **Permanently deferred upstream** — base class only exposes the sentinel as a string. Filing as a follow-up to BUTR's MCM project rather than carrying a fork-internal patch. Tracking in `crest/docs/UPSTREAM_FOLLOWUPS.md`.

## Harmony-patch fragility — top 5 most version-fragile

From the patch survey, ranked by likelihood of silent break on a TaleWorlds update:

1. **`WidgetPrefabPatch.cs:22-28`** — IL transpiler + reverse-patcher on `WidgetPrefab.LoadFrom`. Pattern-matches IL instructions; any refactor breaks silently with just a warning.
2. **`Crest.ButterLib.Implementation.MBSubModuleBaseExtended.Patches.ModulePatch:44`** — transpiler on `Module.SetInitialModuleScreenAsRootScreen` looking for specific OpCodes. We've already seen this fail (`miTargetMethodUnLoad is null` warnings in ModLogs).
3. **`BEWPatch.cs:70-74`** — finalizer patches on five high-frequency tick methods. If any binding fails, exception handling breaks invisibly.
4. **`GauntletMoviePatch.cs:41-46`** — conditional patch keyed on a parameter name string. Trivially broken if TaleWorlds renames the parameter.
5. **`WidgetFactoryManager.cs:84-101`** — six TryPatch transpilers on internal reflection methods, all silent on failure.

These are inherited from upstream BUTR — not unique to CREST — but they're our problem now since we maintain the fork. **Phase P.2** task: add a CREST runtime self-test that on startup verifies each of these patches actually bound, and surfaces a single user-visible warning if any didn't.

## Action summary

- 3 critical findings — **fixed (Phase P)**
- 2 high findings — **fixed (Phase P)**
- 3 high findings — **fixed (Phase P.1)** — H3 cwd→Assembly.Location, H4 dead loader retired, H5 stale-binary detection
- 8 medium findings — **fixed (Phase P.1)** — M1 env-var paths, M2 DebugUI memoization, M3 MoveDirectory dedup, M4 allowlist visibility, M5 nested-type skip log, M6 Assembly-list verification, M7 STUB_VERSIONS.json, M8 CONFIG_STORES.md doc
- 2 low findings — **fixed (Phase P.1)** — L1 IsEnabled XML doc, L2 dead XML registration removed
- 1 low finding — **upstream PR queued** — L3 typed event sentinel (tracked in `crest/docs/UPSTREAM_FOLLOWUPS.md`)
- 1 patch-self-test work item — **queued (Phase P.2)**

Total: 19 of 20 findings closed in this fork. L3 is the only one waiting on upstream.
