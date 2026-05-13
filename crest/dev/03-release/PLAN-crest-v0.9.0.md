# PLAN: CREST v0.9.0 release (Battle Convergence disabled)

Per START.md rule 0.7-equivalent for releases: this is the SINGLE
SOURCE OF TRUTH for the CREST v0.9.0 release. Consult before any
file change to the release artifact under
`C:\dev\bannerlord\crest\dist\release\v0.9.0\`.

## Identity

   release id     : crest-v0.9.0
   module id      : CREST (unchanged)
   display name   : CREST -- Calradian Runtime Extensions & Standard Toolkit
   subtitle (opt) : "Battle Convergence disabled in v0.9.0 -- v1.0.0 will re-enable"
   version        : v0.9.0  (pre-1.0; honest about Battle Convergence regression)
   license        : MIT
   ship to        : Nexus Mods + GitHub release page

## Numbered decisions (locked)

   01. Distribution        Nexus Mods + GitHub release page
   02. Module identity     keep "CREST" name + module id; same display name
   03. Package contents    DLL bundle + SubModule.xml + crest.json + README + CHANGELOG + LICENSE
   04. Features INCLUDED   campaign tweaks, companion hotswap, battle size, tier unlocker,
                           faster time, cut-through-everyone, brush race finalizer,
                           MCM settings UI, player invincible damage clamp
   05. Features EXCLUDED   Battle Convergence (default-off), Cinema preset auto-enable
                           on new install, Crest Dev Console (default-off)
   06. Default crest.json  EnableBattleConvergence: false
                           EnableCampaignTweaks: true
                           EnableCompanionHotswap: true
                           EnableBattleSize: true
                           EnableTierUnlocker: true
                           EnableFasterTime: false
                           EnableCutThroughEveryone: false
                           EnablePlayerInvincible: false
                           EnableBrushRaceMitigation: true
                           EnableCinemaPreset: false
   07. DLL source          ship the dist\staging\ May 8 build (sha 38694C9BCEC1)
                           DEPRECATED: was originally .bak (sha 8999B4950CFB).
                           User asked to switch to the May 8 staging snapshot
                           because Battle Convergence was less unstable in
                           that revision (smaller, fewer Y.6x changes,
                           pre-dates the source-tree corruption).
   08. Version number      v0.9.0
   09. Release notes       short and honest about Battle Convergence regression
   10. License             MIT
   11. Hosting             Nexus account + public GitHub repo, banner image, no clip
   12. Support             GitHub Issues primary, Nexus comments secondary

## MVP scope

   Zipped Modules\CREST\ folder containing:
     - bin\Win64_Shipping_Client\Crest.Harmony.dll       (the .bak)
     - bin\Win64_Shipping_Client\<all sibling DLLs>      (BUTR + shims)
     - SubModule.xml
     - crest.json                                        (locked defaults above)
     - README.md
     - CHANGELOG.md
     - LICENSE

   Acceptance: extract zip into a clean Mount & Blade II Bannerlord\Modules\
   folder, launch via BLSE LauncherEx, enable CREST, run a battle.
   Battle runs without crash. No Y.42 cycle lines in runtime.log
   (Battle Convergence disabled). MCM settings UI shows the CREST
   toggle list. Closing the game leaves no broken state.

## Out of scope (v0.9.0)

   - Battle Convergence functionality (code shipped but disabled)
   - HERALD Marshal integration (separate module, separate release)
   - AppCreate
   - Auto-update mechanism
   - Multi-language support
   - Compatibility patches for Realistic Battle Mod / RBM
   - Steam Workshop publication

## Phase roadmap

   R.1  scaffold        write PLAN.md (this file), create dist\release\v0.9.0\
                        folder structure, write README/CHANGELOG/LICENSE
   R.2  package         copy .bak DLL bundle + SubModule.xml into release root,
                        set crest.json defaults
   R.3  smoke test      extract release zip into a temp folder, verify file
                        layout matches what Bannerlord expects
   R.4  zip + checksum  produce crest-v0.9.0.zip + sha256 alongside
   R.5  publish         (manual) Nexus upload + GitHub release tag

   R.1-R.4 ship in this session. R.5 is a user-driven manual step.

## Performance targets

   - zip size            target < 10 MB; should land ~5 MB
   - cold install        user extracts + launcher recognizes module
                         in < 30 sec
   - first battle load   no perceptible regression vs. running CREST
                         from the dev folder

## Risk register

   01. Battle Convergence accidentally enabled
       why: someone manually flips EnableBattleConvergence to true
            and hits the regression we documented in MISSION-PROGRESS.md
       mitigation: README warns explicitly; CHANGELOG explains why
                   it is off; in-game MCM UI tooltip notes the
                   experimental status

   02. crest.json defaults accidentally bundle a different value
       why: dev tree's crest.json has different runtime values from
            our release default set
       mitigation: do NOT copy the deployed crest.json verbatim;
                   write a fresh release crest.json from this PLAN
                   table

   03. .bak DLL turns out to be missing a sibling
       why: the BUTR shim DLLs (Bannerlord.Harmony.dll, MCMv5.dll,
            etc.) live next to .bak; if any are stale or missing,
            consumer mods break
       mitigation: copy the full bin\Win64_Shipping_Client\ contents
                   minus the .crashed-* and .bak files; verify no
                   missing siblings against a fresh BLSE launch

   04. License header missing from source
       why: MIT requires a LICENSE file but technically also a header
            in each source file. We are NOT shipping source in this
            release, only binary, so headers are optional.
       mitigation: ship only the LICENSE file in v0.9.0; add file
                   headers if/when we ship source

   05. Nexus upload metadata wrong
       why: required fields (game, category, tags) need correct values
       mitigation: README documents the correct Nexus form values
                   so the user can fill them in by copy-paste

## Decisions deferred

   - Whether to ship a "lite" version with ONLY campaign tweaks
     (no in-mission features at all). Probably v1.1.0.
   - Whether to ship a per-user telemetry opt-in to learn which
     features people actually enable. Probably never.
   - Whether to bundle a sample crest.json with Battle Convergence
     pre-enabled for advanced users. Probably no -- they edit
     manually if they want it.

## Compatibility surface

   Bannerlord       v1.4.3.0 (CREST's tested target)
   BLSE             1.6.5.0 minimum
   .NET             4.7.2 (loaded by the game)
   OS               Windows 10/11 (the game's supported OS)
   other mods       loads alongside BLSE, BUTR stack, Bannerlord.Harmony,
                    Bannerlord.ButterLib, Bannerlord.UIExtenderEx, MCMv5
                    -- those are CREST's parents in the load order

## How to update this plan

   When the release scope or contents change, edit THIS file in
   the same change as the artifact change. Past decisions get a
   "DEPRECATED:" note rather than being deleted, so the rationale
   trail survives.

   Subsequent releases (v0.9.1, v0.10.0, v1.0.0) get their own
   PLAN-crest-v<X.Y.Z>.md file in this folder. Do NOT mutate this
   v0.9.0 plan.
