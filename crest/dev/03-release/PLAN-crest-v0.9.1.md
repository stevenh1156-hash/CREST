# PLAN: CREST v0.9.1 release (Vanilla preset + ATC bundling)

Per START.md rule 0.8, this is the SINGLE SOURCE OF TRUTH for the
CREST v0.9.1 release. Consult before any change to the v0.9.1
release artifact under `C:\dev\bannerlord\crest\dist\release\v0.9.1\`.

Scope: a small follow-up to v0.9.0 that adds two user-facing features
without re-enabling Battle Convergence (that stays for v1.0.0).

## Identity

   release id     : crest-v0.9.1
   ships after    : v0.9.0
   ships before   : v1.0.0 (Battle Convergence re-enable)

## Numbered decisions (locked)

   01. Scope        small follow-up; no Battle Convergence re-enable
   02. Three features for v0.9.1: Vanilla preset + CrashMirror + 1.3.14 build variant.

   01b. 1.3.14 support implementation:
                    - add a second build target to Crest.Harmony.csproj
                      that pins Bannerlord.ReferenceAssemblies.Core to a
                      1.3.14-compatible version
                    - ship TWO release zips: crest-v0.9.1-game1.4.x.zip
                      and crest-v0.9.1-game1.3.14.zip
                      (separate Nexus file entries on the same mod page)
                    - same source tree, same crest.json defaults; only
                      the bundled DLLs differ (compiled against
                      different ReferenceAssemblies versions)
                    - add a "Game version" picker on the Files tab so
                      Nexus users can grab the right zip
                    - acceptance: zip the 1.3.14 variant, install on a
                      Bannerlord 1.3.14 machine, launch, see CREST in
                      the module list, run a battle without the vanilla
                      crash uploader popup
                    - risk: BUTR libraries may not have a clean 1.3.14
                      release; if so, drop 1.3.14 from v0.9.1 and move
                      to v0.9.2.
                    DEPRECATED: was originally Vanilla preset + ATC
                    bundling. ATC bundling pulled because Adonnay's
                    license needs verification before we redistribute;
                    deferred to v0.10.0+. CrashMirror added in its
                    place because it is a small lift that materially
                    improves bug-report quality (one path for users
                    instead of two).
   02b. CrashMirror implementation:
                    - new MissionBehavior `CrestCrashMirror` registered
                      at OnSubModuleLoad
                    - OnApplicationTick (every N seconds, default 5)
                      probes %USERPROFILE%\Documents\Mount and Blade II
                      Bannerlord\crashes\ for new crashreport*.html
                      files modified after the module's start time
                    - copies any new file into Modules\CREST\crashes\
                      (atomic copy via .tmp + rename)
                    - logs each mirror to runtime.log so users can
                      grep "[CrestCrashMirror]" to find what got copied
                    - gated on EnableCrashMirror config flag (default
                      true). Disable via MCM if user does not want
                      the duplicate.
                    - one new file: CrestCrashMirror.cs (~120 lines)
                    - SubModule.cs registers it next to other
                      SubModuleBase overrides
                    - new crest.json key: "EnableCrashMirror": true
   03. Vanilla preset implementation:
                    - new MCM toggle "Preset" with options:
                      Default / Vanilla / Cinema
                    - "Vanilla" sets every CREST EnableXxx flag to false
                      via crest.json rewrite + immediate in-mission effect
                      where possible
                    - "Cinema" enables FasterTime + CutThroughEveryone
                      + PlayerInvincible (the existing cinema features)
                    - "Default" is what crest.json shipped with
                    - one new file: CrestPresets.cs (~150 lines)
                    - one MCM page change: add the preset dropdown
   04. ATC bundling implementation:
                    - download Adonnay's Troop Changer source from Nexus
                      mod #286 OR fork the GitHub repo
                    - rebrand under Crest.Adonnay.* namespace following
                      the same pattern as Crest.Harmony et al.
                    - ship a Bannerlord.Adonnay.dll (or whatever name
                      ATC uses) type-forwarding compatibility shim
                    - add to SubModule.xml Assemblies block
                    - add to crest.json defaults: EnableTroopChanger
                      (default true)
                    - update THIRD-PARTY-LICENSES.txt with ATC's license
                      (verify on Nexus -- likely MIT or similar)
   05. crest.json schema additions:
                      - "Preset": "Default"  (string enum)
                      - "EnableTroopChanger": true
   06. Re-zip + new SHA256
   07. Distribution channels: same as v0.9.0 (Nexus + GitHub release)

## MVP scope

   Vanilla preset MVP: player launches the v0.9.1 build, opens
   MCM -> CREST -> Preset dropdown, picks "Vanilla". Every CREST
   feature toggle goes to OFF. Game restart confirms the new state
   holds in crest.json. Pick "Cinema" -- the three cinema features
   turn on. Pick "Default" -- back to v0.9.0 defaults.

   CrashMirror MVP: player crashes the game. After they re-launch,
   they look in Modules\CREST\crashes\ and find a copy of the same
   crashreport-*.html that BUTR.CrashReport wrote to Documents\
   ...\crashes\. Filename matches. SHA matches. They can attach the
   mod-folder copy to a GitHub Issue without ever leaving the
   Modules\CREST tree.

## Out of scope (v0.9.1)

   - Battle Convergence (still disabled by default, fix landing in v1.0.0)
   - HERALD Marshal integration
   - New campaign tweaks beyond what v0.9.0 ships
   - New in-mission features beyond Vanilla/Cinema preset switching

## Phase roadmap

   R.1  scaffold       DONE -- dist/release/v0.9.1/Modules/CREST/ created
                       from v0.9.0 baseline.
   R.2  Vanilla preset DONE -- CrestPresets.cs written (~317 lines).
                       Wired via Ctrl+Alt+1/2/3 hotkeys (chosen over MCM
                       dropdown to avoid touching the MCM UI assembly,
                       which is not in the Bannerlord.Harmony source
                       tree). Default/Vanilla/Cinema each apply atomic
                       crest.json rewrite (.tmp + rename). NotifyApplied
                       displays a CREST-gold toast confirming the swap.
   R.3  CrashMirror    DONE -- CrestCrashMirror.cs written (~179 lines).
                       Registered in SubModule.OnSubModuleLoad
                       (Initialize) and SubModule.OnApplicationTick
                       (OnTick, 5-second internal cadence). Copies
                       crashreport*.html from Documents\...\crashes\ to
                       Modules\CREST\crashes\ atomically. Gated on
                       EnableCrashMirror (default true). Idempotent via
                       HashSet of mirrored filenames.
   R.4  1.3.14 variant DONE -- no csproj edit needed; the existing
                       Version="$(GameVersion).*-*" already accepts
                       command-line override. Build-Release-V0.9.1.ps1
                       drives both -p:GameVersion=1.4.2 and
                       -p:GameVersion=1.3.14 builds with separate
                       BaseOutputPath=bin1314\ to keep outputs isolated.
                       SubModule.xml's <Version> is patched to v1.3.14
                       at packaging time for the 1.3.14 zip. If the
                       1.3.14 build fails (BUTR ReferenceAssemblies
                       1.3.14 unavailable on NuGet), only the 1.4.x zip
                       ships; 1.3.14 slips to v0.9.2.
   R.5  package + docs DONE -- README + CHANGELOG + crest.json updated.
                       Build-Release-V0.9.1.ps1 produces both zips +
                       SHA-256 sidecars in dist/release/ when run.
   R.6  publish        USER STEP -- run Build-Release-V0.9.1.ps1 on dev
                       box (needs SDK + game install for the BUTR
                       ReferenceAssemblies NuGet feed), upload both zips
                       to Nexus on the same mod page (Game version =
                       1.4.x and Game version = 1.3.14), update mod
                       description to mention v0.9.1, tag GitHub release.

## Performance targets

   - preset switch              < 5 ms (just JSON rewrites + in-mem flag flip)
   - ATC patches at module load < 50 ms additional (one Harmony patch
                                target per ATC feature)
   - zip size                   < 8 MB (target; ATC source is small)

## Risk register

   01. ATC license incompatibility
       why: ATC may be GPL or some non-MIT license that conflicts with
            CREST's MIT redistribution model
       mitigation: check ATC's LICENSE file on Nexus / GitHub before
                   starting R.3. If GPL, two options: (a) pivot to a
                   pure runtime-patch approach where we don't redistribute
                   ATC source, just install matching Harmony patches
                   ourselves; (b) keep ATC as a separate optional
                   Required Mod the user installs alongside CREST.

   02. Preset switch breaks in-mission state
       why: MCM lets users change settings during a mission; if "Vanilla"
            disables CompanionHotswap mid-mission while the player is
            controlling a swapped companion, weird behavior may occur
       mitigation: preset changes apply to crest.json immediately, but
                   in-mission features only re-evaluate at next mission
                   start. Document this in MCM tooltip.

   03. crest.json corruption
       why: Vanilla preset rewrites crest.json; if write fails midway
            user loses all settings
       mitigation: write to crest.json.tmp first then atomic rename
                   (same pattern Crest-Postmortem uses for digest)

## Decisions deferred

   - Whether to add a custom preset slot ("Save current as preset X")
     -- probably v0.10.0 if at all.
   - ATC (Adonnay's Troop Changer) bundling -- deferred from v0.9.1
     to a future release. License verification needed first.
   - Shim-layer deprecation timing -- the public commitment is now
     12+ months of post-deprecation shim support, but the actual
     deprecation announcement date is TBD. Likely after v1.0.0
     when CREST's Crest.* assemblies have stabilized.
   - Whether to emit telemetry on which preset is picked. No.

## Compatibility surface

   Bannerlord    v1.4.3.0 (same as v0.9.0)
   BLSE          1.6.5.0+ (same as v0.9.0)
   .NET          4.7.2 (same as v0.9.0)
   load order    Native -> SandBoxCore -> SandBox -> StoryMode ->
                 CustomBattle -> CREST (same as v0.9.0)

## How to update this plan

   When the scope shifts (e.g. ATC turns out to be GPL and we drop
   it from v0.9.1), edit THIS file in the same change. Past
   decisions get a "DEPRECATED:" note rather than being deleted.

   v1.0.0 gets its own PLAN-crest-v1.0.0.md when scope stabilizes.
