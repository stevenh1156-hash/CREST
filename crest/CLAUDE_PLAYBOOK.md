# CREST Hotfix & Update Playbook

**Audience:** Claude (or any agent) coming back to this codebase to ship a small
fix to a live CREST install. Read this first — it covers the build pipeline,
the dual-branch architecture, the diagnostic file locations, and the common
bug patterns we keep hitting. Pair with `CODE_INDEX.md` for symbol-level
navigation.

Last updated: 2026-05-10 (after the e1.4.x beta options-menu CTD + BEW finalizer
binding fixes).

---

## 1. Filesystem layout (memorize these paths)

| What                           | Path                                                                                              |
| ------------------------------ | ------------------------------------------------------------------------------------------------- |
| Source tree root               | `C:\dev\bannerlord\`                                                                              |
| CREST repo (build/dist scripts)| `C:\dev\bannerlord\crest\`                                                                        |
| Crest.Harmony source           | `C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\`                                         |
| Crest.Harmony.Beta source      | `C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony.Beta\`                                    |
| Crest.ButterLib source         | `C:\dev\bannerlord\Bannerlord.ButterLib\src\Crest.ButterLib\`                                     |
| Crest.MCM.UI source            | `C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI\`                                |
| **Live game install (Steam)**  | `C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\`        |
| Live install bin folder        | `…\Modules\CREST\bin\Win64_Shipping_Client\`                                                      |
| **Diagnostic log**             | `…\Modules\CREST\runtime.log`                                                                     |
| Crash reports (mirrored)       | `…\Modules\CREST\crashes\`                                                                        |
| BUTR original crashes          | `%USERPROFILE%\Documents\Mount and Blade II Bannerlord\crashes\`                                  |
| Bannerlord native rgl_log      | `%USERPROFILE%\OneDrive\Documents\Mount and Blade II Bannerlord\Logs\` (with OneDrive redirection)|
| Release dist (canonical)       | `C:\dev\bannerlord\crest\dist\release\v0.9.1\Modules\CREST\`                                      |

The user's "Documents" folder is OneDrive-redirected. Native Bannerlord crash
logs go there, not to `C:\Users\<u>\Documents\…`. CREST's runtime.log goes to
the Modules folder regardless.

---

## 2. Build infrastructure

### dotnet SDK
- Windows side: `dotnet 10.0.300-preview.0.26177.108` is installed at
  `C:\Program Files\dotnet\`. Builds work in 2–5 seconds per project.
- The Linux sandbox (workspace bash) does NOT have dotnet installed. Don't
  try `dotnet build` in the sandbox; build via the Windows runner or via
  PowerShell directly.

### Agent runner (.runner)
- Lives at `C:\dev\bannerlord\crest\.runner\`.
- Watches `.runner\queue\*.ps1`, moves accepted scripts into `loop\`, then to
  `done\` when finished. Output logs land in `.runner\results\`.
- **Runner can be down.** It went idle around 19:02 on 2026-05-10 and didn't
  pick up new scripts for 1.5+ hours. If `done\` mtime is more than ~10 min
  stale and `queue\` has pending scripts, assume the runner is asleep.
- Heartbeat files: `watcher-last-pm-seen.txt`, `watcher-last-ready-seen.txt`.
  Compare to `date` for liveness.

### Manual fallback (when runner is dead)
The user is at the keyboard most of the time. Drop the script in
`.runner\queue\` so it's preserved on disk, then have them run it directly:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\dev\bannerlord\crest\.runner\queue\<script-name>.ps1"
```

**Run as Admin** because the game install is under `Program Files (x86)`.
The script must `Stop-Process bannerlord -ErrorAction SilentlyContinue` or
the user must be told to close Bannerlord first; otherwise the DLL is locked
and the copy fails.

### Build script template
A minimal "patch one project, deploy DLL, optionally deploy README" script:

```powershell
$ErrorActionPreference = 'Stop'
Write-Host '== <descriptive title> ==' -ForegroundColor Cyan

$Csproj  = 'C:\dev\bannerlord\<path>\<Project>.csproj'
$BuildOut = 'C:\dev\bannerlord\<path>\bin\Release\net472'
$LiveBin  = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'

# Step 1: build
& dotnet build $Csproj -c Release -f net472 --nologo 2>&1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Step 2: verify
$BuiltDll = Join-Path $BuildOut '<Project>.dll'
$BuiltPdb = Join-Path $BuildOut '<Project>.pdb'
if (-not (Test-Path $BuiltDll)) { exit 1 }
$dllInfo = Get-Item $BuiltDll
Write-Host ("  built : {0}  size={1}" -f $BuiltDll, $dllInfo.Length)

# Step 3: deploy
Copy-Item -Force $BuiltDll (Join-Path $LiveBin '<Project>.dll')
if (Test-Path $BuiltPdb) { Copy-Item -Force $BuiltPdb (Join-Path $LiveBin '<Project>.pdb') }

Write-Host '== complete ==' -ForegroundColor Green
```

Build outputs by project:
| Project              | Output path (relative to project)                  | Live name              |
| -------------------- | -------------------------------------------------- | ---------------------- |
| Crest.Harmony        | `bin\Stable_Release\net472\Crest.Harmony.dll`      | `Crest.Harmony.dll`    |
| Crest.Harmony.Beta   | `bin\Release\net472\Crest.Harmony.Beta.dll`        | `Crest.Harmony.Beta.dll`|
| Crest.ButterLib      | `bin\Release\net472\Crest.ButterLib.dll`           | `Crest.ButterLib.dll`  |

Crest.Harmony specifically uses `Stable_Release` config because the project
sets `<PublicGameVersion>1.3.15</PublicGameVersion>` for the public branch
build. Crest.Harmony.Beta uses plain `Release` with `<GameVersion>1.4.2</GameVersion>`
hardcoded in the csproj.

---

## 3. The dual-branch architecture (NEVER collapse this)

CREST ships ONE zip that runs on both Bannerlord public (e1.3.x) and beta
(e1.4.x). The mechanism:

- **`Crest.Harmony.dll`** — built against 1.3.x reference assemblies. Loads
  on every install. Carries every always-safe patch (FindText cleanup, brush
  race finalizer, MaxBattleSize cap, naval postfix, campaign tweaks, etc.).
- **`Crest.Harmony.Beta.dll`** — built against 1.4.x reference assemblies.
  Loaded ONLY on e1.4.x+ installs by `CrestBetaBridge.TryLoadAndInitialize`,
  which probes `Modules\Native\SubModule.xml` for the version. References
  TaleWorlds 1.4-only types (`DefaultBattleMissionAgentSpawnLogic`,
  `MissionBattleSideSpawnContext`) that don't exist on 1.3.x — compiling
  these into the public DLL would CTD on launch on every public install.
- **Bridge:** `Bannerlord.Harmony.CrestBetaBridge` holds delegate fields
  (`RegisterBetaPatches`, `AddConvergenceMissionBehavior`) that the main DLL
  invokes. On public installs the delegates stay null and the corresponding
  features silently no-op.

If a fix only touches always-safe behavior, edit `Crest.Harmony` and rebuild
that. If a fix touches 1.4-only TaleWorlds API, it goes in `Crest.Harmony.Beta`.
**Don't** try to consolidate — the split exists for a real load-time reason.

`Crest.ButterLib`, `Crest.UIExtenderEx`, `Crest.MCM`, `Crest.MCM.UI` are all
single DLLs (no public/beta split). Their patch targets exist on both branches.

---

## 4. Diagnostic file locations

The user routinely hunts for these and gets confused — point them here first.

1. **`Modules\CREST\runtime.log`** — CREST's own diag. Every patch bind
   outcome (`OK` / `HARD miss` / `SOFT miss` / `skipped`), every caught
   exception, every BEW finalizer fire. Buffered 1Hz writer. **First file
   to read for any CREST issue.**
2. **`Modules\CREST\crashes\`** — BUTR HTML crashreports, mirrored from
   `%USERPROFILE%\Documents\Mount and Blade II Bannerlord\crashes\` on a
   5-second tick by CREST's CrashMirror feature.
3. **OneDrive\Documents\Mount and Blade II Bannerlord\Logs\\rgl_log_*.txt** —
   Bannerlord's native engine log. NOT in `C:\Users\<u>\Documents\` because of
   OneDrive Documents redirection. Often empty when a hard CTD happened
   below the engine logger's reach.

If runtime.log shows `[CrestPatchSelfTest]` lines, the self-test is running.
HARD misses there are real bugs to investigate. SOFT misses are tolerated
(e.g. UIExtenderEx transpilers that bind by signature, not by name).

---

## 5. Bisection methodology (when no log tells you what crashed)

If a hard CTD happens with no log artifact, isolate by disabling DLLs:

```bash
# In bash sandbox (mount path):
mv ".../Modules/CREST/bin/Win64_Shipping_Client/Crest.<X>.dll" \
   ".../Modules/CREST/bin/Win64_Shipping_Client/Crest.<X>.dll.disabled"
mv ".../Modules/CREST/bin/Win64_Shipping_Client/Crest.<X>.pdb" \
   ".../Modules/CREST/bin/Win64_Shipping_Client/Crest.<X>.pdb.disabled"
```

Restart, repro. If gone → that DLL contains the offender. Half-split from there.

Useful disable points:
- `Crest.Harmony.Beta.dll` — disables only the Beta-only patches. Public DLL
  still loads. The bridge logs `Crest.Harmony.Beta.dll not found` and
  silently moves on.
- `Crest.UIExtenderEx.dll` / `Crest.MCM.UI.dll` — disables UI extension
  layer; useful if a UI screen is the crash trigger.

After bisection isolates a DLL, grep its source for any patch on the type
the user is touching when the crash hits.

---

## 6. Common bug patterns + fix templates

### Pattern A: Beta-branch TaleWorlds signature drift
Symptom: hard CTD when the game touches a particular UI/mission code path.
No `rgl_log` written, no BEW popup, no managed exception. CrestPatchSelfTest
shows the patch as `OK` (it bound), but invocation explodes.

Cause: `AccessTools2.Method("Type:Method")` resolved a method whose return
type or parameter shape changed on the new beta. Harmony built the patch
delegate around the old shape; first invocation pushes the wrong values
into the postfix's stack frame → native fault.

Fix template — pre-bind signature verification:

```csharp
private static void BindStatic(HarmonyLib.Harmony h, string typeName, string method,
    string handler, string label,
    Type? expectedReturnType = null, int? expectedParamCount = null)
{
    try
    {
        var t = AccessTools2.TypeByName(typeName);
        if (t == null) { CrestDiag.Log(Source, label + " skipped: type missing"); return; }
        var m = AccessTools2.Method(t, method);
        if (m == null) { CrestDiag.Log(Source, label + " skipped: method missing"); return; }

        if (expectedReturnType != null && m.ReturnType != expectedReturnType)
        {
            CrestDiag.Log(Source, label + " skipped: return type mismatch (got "
                + m.ReturnType.FullName + ", expected " + expectedReturnType.FullName + ")");
            return;
        }
        if (expectedParamCount != null && m.GetParameters().Length != expectedParamCount.Value)
        {
            CrestDiag.Log(Source, label + " skipped: param count mismatch (got "
                + m.GetParameters().Length + ", expected " + expectedParamCount.Value + ")");
            return;
        }

        h.Patch(m, postfix: new HarmonyMethod(typeof(MyPatchClass), handler));
    }
    catch (Exception ex) { CrestDiag.LogCaught(Source, label + " bind", ex); }
}
```

Apply this pattern to every Crest.*.Beta patch site that targets a 1.4-only
TaleWorlds method. Also wrap the postfix body itself in try/catch as a
belt-and-suspenders second layer (managed exception inside the postfix is
catchable and loggable; the unmanaged crash before invocation is not).

Real instance fixed today: `CrestBattleSizeBetaPatches.MaxTroopsPostfix` on
`DefaultBattleMissionAgentSpawnLogic.get_MaxNumberOfTroopsForMission`.

### Pattern B: BLSE-gated subsystem isn't actually doing what it thinks BLSE does
Symptom: a Crest.* subsystem's self-test reports `HARD` for patches the
subsystem is supposed to install. Often the binding code has an
`if (!_wasButrLoaderInterceptorCalled)` style gate that skips the bind on
the assumption "BLSE will install equivalent patches." Empirically BLSE
doesn't always cover the same set.

Real instance fixed today: `Bannerlord.ButterLib.ExceptionHandler.ExceptionHandlerSubSystem.Enable()`
was skipping `BEWPatch.Enable(Harmony)` on every BLSE-launched install. BLSE's
own `FinalizerGlobal` only patches `*CallbacksGenerated` methods — disjoint
from BEW's tick-path targets (`Mission.Tick`, `Module.OnApplicationTick`,
`ScreenManager.Tick`, `ManagedScriptHolder.TickComponents`,
`Managed.ApplicationTick`). Result: every install had no tick-path crash
safety net.

Fix: remove the gate. Double-binding is harmless because Harmony chains
finalizers. Also wrap each individual `harmony.Patch` in a defensive
`TryPatchOne(harmony, methodInfo, label)` helper so a single null
`MethodInfo?` doesn't NRE the whole call chain.

### Pattern C: Unbinding helpers that do nothing useful
Files like `BEWPatch.cs` had a `Disable(Harmony)` symmetric to `Enable`.
If you disable the bind, also remember to disable the corresponding
`Disable` path or it'll throw on missing patch.

---

## 7. Cross-DLL logging via reflection
`Crest.ButterLib` (and other non-Harmony DLLs) reach `CrestDiag.Log` through
reflection because compile-time-direct reference would create a cyclic dep:

```csharp
private static void DiagLog(string source, string message)
{
    try
    {
        var crestDiagType = Type.GetType("Bannerlord.Harmony.CrestDiag, Crest.Harmony");
        var logMethod = crestDiagType?.GetMethod("Log",
            BindingFlags.Public | BindingFlags.Static, null,
            new[] { typeof(string), typeof(string) }, null);
        logMethod?.Invoke(null, new object[] { source, message });
    }
    catch { /* never let mirror-logging failure block the bind. */ }
}
```

Crest.Harmony loads first in the SubModule chain, so by the time anything
else logs, CrestDiag is available.

---

## 8. Verification checklist after a fix lands

1. **Did the build script complete green?** Look for the final
   `== complete ==` line in PowerShell output.
2. **Is the live DLL the right size?** Compare live mtime + size to
   `Bannerlord.<X>\src\<Project>\bin\Release\net472\<Project>.dll`.
3. **Does runtime.log show the new bind lines?** After launching the game,
   `tail` runtime.log and grep for the labels you added in the fix.
4. **Did the relevant `[CrestPatchSelfTest]` HARD entries flip to OK?**
   Self-test runs at startup; results land in runtime.log.
5. **Does the user's repro path no longer CTD?** Have them retest the
   exact UI screen / button / mission action that triggered the bug.

---

## 9. Today's fixes summary (2026-05-10)

For reference when reading `git log` and wondering what these patches did:

| File                                                                             | Change                                                                                                |
| -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `Bannerlord.Harmony\src\Crest.Harmony.Beta\CrestBattleSizeBetaPatches.cs`        | Added pre-bind sig check to `BindStatic` + try/catch wrapper around `MaxTroopsPostfix`. Fixes Beta options-menu CTD. |
| `Bannerlord.ButterLib\src\Crest.ButterLib\ExceptionHandler\ExceptionHandlerSubSystem.cs` | Removed `_wasButrLoaderInterceptorCalled` gate around `BEWPatch.Enable(Harmony)`. Forces BEW finalizers to bind on BLSE-launched installs. |
| `Bannerlord.ButterLib\src\Crest.ButterLib\ExceptionHandler\BEWPatch.cs`          | Replaced 5 raw `harmony.Patch` calls with a defensive `TryPatchOne` helper + `DiagLog` reflection-into-CrestDiag mirror. |
| `crest\dist\release\v0.9.1\Modules\CREST\README.md`                              | Added "Where to find logs" section + Troubleshooting callout pointing at `Modules\CREST\runtime.log`. |

All four changes are additive on the v0.9.1 dual-branch architecture, not
replacements for it. Roll into v0.9.2 by rebuilding `Crest.Harmony.Beta.dll`
and `Crest.ButterLib.dll` plus copying the new README into
`dist\release\v0.9.1\Modules\CREST\` (or rename the dir for a v0.9.2 dist).

---

## 10. Hard-won lessons (added during the v0.9.2 bundle)

### Verifying string constants are present in a built DLL
.NET stores user string literals in the `#US` (User String) heap of the
assembly metadata as **UTF-16 LE** with **variable-width length prefixes**
(1-3 bytes depending on string length). This has two implications for any
"is my source change actually in the DLL?" sanity check:

1. **Don't use the Linux `strings` command without `-e l`.** Default `strings`
   only finds ASCII runs of printable chars and silently misses every UTF-16
   string in a managed DLL. Use `strings -e l <file.dll> | grep <needle>`
   for little-endian UTF-16. This is the simplest reliable check.

2. **Don't decode the entire DLL byte stream as UTF-16 in PowerShell.** The
   tempting `[Encoding]::Unicode.GetString($bytes).Contains($needle)` approach
   produces false negatives because the user string heap has odd-byte length
   prefixes that knock the alignment off, garbling the decoded output. Linux
   `strings -e l` does an alignment-tolerant scan and works correctly; the
   PowerShell one-liner equivalent is harder than it sounds. If you must
   verify in PowerShell, load the assembly with `System.Reflection.Metadata`
   and walk the user-string heap explicitly, or just shell out to a tool
   that knows about CLR metadata.

A bundling pipeline that fails-fast on missing sentinels is good in
principle but only as good as the sentinel detector. Today's bundling lost
30 minutes to a broken PowerShell sentinel check; eventually we just
verified via Linux `strings -e l` and skipped the in-script check entirely.

### Linux mount staleness vs Windows-side reality
The `/sessions/.../mnt/` mount that the agent reads from can show STALE
file metadata (mtime, size) for files that were recently written on the
Windows side, even when the *content* is fresh. Symptoms:
- `stat` shows a several-day-old mtime and pre-edit byte size
- `Read`/`grep` returns the current Windows-side content correctly
- Bin output (`bin/Release/.../*.dll`) on the mount can be stale too

When mtimes look impossibly old, **trust file content over file metadata**.
Use Windows-side PowerShell (`Get-Item`, `Get-Content`) for ground truth.

### Live-install DLLs can revert silently
The user's live install `Crest.Harmony.Beta.dll` reverted from the deployed
fixed version (80384 bytes) back to a pre-fix version (79872 bytes from
2:51 PM, before any of today's work) at some point during the session,
without any obvious cause. The user's other deployed DLLs stayed correct.
This is documented for awareness — when the user reports "the fix isn't
working," consider whether the live install file actually has the fix code
(check via `strings -e l` or via a re-deploy from `bin/Release`) before
assuming a logic bug.

### Bundle pipeline: prefer `bin/Release` over live install as source of truth
Live install DLLs can revert (see above) and can be partial (only some of
the deployment scripts touch some of the DLLs). When bundling a release,
copy from each project's `bin/Release/<framework>/` output, not from the
game's live install. The bundling script `agent-bundle-v092-from-bin-*.ps1`
in `.runner/done/` is the working template.

### v0.9.2 release artifacts (2026-05-10)

   - zip: `C:\dev\bannerlord\crest\dist\release\crest-v0.9.2.zip` (7.72 MB)
   - sha: `dbc33eeb222c04fc170a56d8908c49c082d229bc2dd7169ece3f5556a488484d`
   - changes: sigsafe Beta binds, BEW finalizer defensive direct call,
     UIExtenderEx PrefabExtension*Attribute → public, README "Where to
     find logs" callout
