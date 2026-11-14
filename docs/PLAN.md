# JimPowerMizer — Plan

Switch graphics settings automatically depending on what the player is doing,
to cut GPU/CPU power draw when full fidelity isn't needed (AFK, flight paths,
sitting in a city, alt-tabbed, etc.), and restore them when it is.

## 1. Target clients

| Flavor | Interface | TOC file | API family | Status |
|---|---|---|---|---|
| **Forever** | `16001` | `JimPowerMizer_Mainline.toc` | Mainline (Midnight 12.x API) | **Primary target** |
| Midnight (Standard) | `120105` | `JimPowerMizer_Mainline.toc` | Mainline | Future (easy, same API) |
| Mists / Cata / Wrath / TBC / Vanilla | `50504` / … / `11509` | `JimPowerMizer_Classic.toc` or per-flavor | Classic | Future |

**Verified on Forever build 1.60.1 (70938), 2026-11-13 (`/jpm probe`, out of combat):**
- Interface `16001`; `WOW_PROJECT_ID` = `WOW_PROJECT_CAMELOT` = `18`.
- All CVars in `Core/CVarRegistry.lua` exist under those names. None is secure, read-only or locked.
- Addon writes via `C_CVar.SetCVar` work (write test on `maxFPSBk` passed).
- In combat (`/jpm probe combat`, `InCombatLockdown()` true): the same flags, and the `maxFPSBk` write test
  also passes. So CVar writes aren't blocked by combat lockdown. Only `maxFPSBk` was write-tested; the
  combat deferral in the Applier stays as a safety net for any CVar the client marks secure.

TOC naming: the BigWigs packager (v2.7.0) recognizes `_Mainline` and `_Camelot` but not `_Forever`, so the
TOC is `JimPowerMizer_Mainline.toc`. Mainline is the client family that includes Forever and Standard.

Notes / things to verify in the live client (sources are beta-era fan sites + Warcraft Wiki):
- `/dump select(4, GetBuildInfo())` → expect `16001`.
- `/dump WOW_PROJECT_ID, WOW_PROJECT_CAMELOT` → `WOW_PROJECT_ID` was reported as `1` on one beta build and `18` (`WOW_PROJECT_CAMELOT`) on a later one. **Don't branch on project ID alone**; check for the specific APIs we use.
- Midnight addon restrictions ("secret values", combat lockdown) apply on Forever. Confirm which graphics CVars can be set by `SetCVar` from addon code, and whether they're blocked in combat.

## 2. Architecture

```
JimPowerMizer/
├── JimPowerMizer_Mainline.toc     # Mainline family (Forever now; Midnight later via a second Interface value)
├── JimPowerMizer_Classic.toc      # (later) Classic family
├── .pkgmeta                       # BigWigs packager: pulls Libs/ as externals
├── embeds.xml                     # loads Libs/
├── Libs/                          # NOT committed; fetched by packager / scripts/fetch-libs.sh
├── Locales/enUS.lua               # AceLocale strings
├── Compat/
│   ├── Compat.lua                 # the interface the rest of the addon uses (ns.Compat)
│   ├── Mainline.lua               # Forever + Midnight implementation
│   └── Classic.lua                # (later) Classic-family implementation
├── Core/
│   ├── Init.lua                   # AceAddon object, namespace, version/flavor detection
│   ├── Database.lua               # AceDB defaults, profiles, migrations
│   ├── CVarRegistry.lua           # known graphics CVars: type, range, per-flavor availability, "needs restart" flag
│   ├── Applier.lua                # snapshot / diff / apply / restore CVars, combat-safe queue
│   └── Engine.lua                 # resolves active situation → profile, debouncing, hysteresis
├── Situations/                    # one file per detector, all register with Engine
│   ├── Idle.lua  Taxi.lua  Resting.lua  Background.lua  Combat.lua
│   ├── Instance.lua  Dead.lua  Cinematic.lua  Vendor.lua (AH/mail/bank open)
├── Profiles/Presets.lua           # built-in graphics presets ("Max saver", "Light saver", ...)
└── Options/
    ├── Options.lua                # AceConfig options table → Blizzard Settings panel
    └── Compartment.lua            # Blizzard addon-compartment (minimap menu) entry
```

### Key design rules
1. **Compat layer is the only place that knows about flavors.** Everything else calls
   `ns.Compat:IsOnTaxi()`, `ns.Compat:IsAFK()`, `ns.Compat:OpenOptions()` etc. Adding a new
   flavor = new `Compat/*.lua` + new TOC + CVar availability entries.
2. **CVarRegistry describes what exists per flavor.** Profiles only reference CVars by key; the
   Applier silently skips CVars the current client doesn't have (`C_CVar.GetCVarInfo` returns nil).
3. **Situations are plugins.** Each exports `{ key, name, priority, events, Evaluate() }`. The Engine
   listens for their events, calls `Evaluate()`, and picks the highest-priority active one.
4. **User's settings are sacred.** The baseline (what the user had before we touched anything) is
   saved to SavedVariables *before* the first change, and restored on: situation ending, addon
   disabled, `/jpm off`, and next login if we were logged out / crashed while in a reduced state.

### Data model (AceDB)
```lua
profile = {
  enabled = true,
  graphicsProfiles = {          -- named CVar sets; nil value = "leave alone"
    ["Max saver"]   = { targetFPS = 15, renderScale = 0.5, graphicsQuality = 1, ... },
    ["Light saver"] = { targetFPS = 30, graphicsShadowQuality = 1, ... },
  },
  situations = {                -- per situation: enabled, profile name, priority, delays
    idle    = { enabled = true, profile = "Max saver",  priority = 90, enterDelay = 120 },
    taxi    = { enabled = true, profile = "Max saver",  priority = 80, enterDelay = 2 },
    resting = { enabled = false, profile = "Light saver", priority = 30 },
    combat  = { enabled = true, profile = nil, priority = 100 }, -- nil = force baseline
  },
}
char/global = {
  baseline = { ... },           -- captured user CVars
  appliedProfile = "taxi",      -- for crash recovery
}
```

## 3. Situations (detectors)

| Situation | Detection (Mainline API) | Default |
|---|---|---|
| **Combat** | `PLAYER_REGEN_DISABLED/ENABLED`, `InCombatLockdown()` | Always restore full settings (highest priority) |
| **Idle** | AFK flag (`PLAYER_FLAGS_CHANGED` + `UnitIsAFK`), plus our own timer: no movement (`PLAYER_STARTED/STOPPED_MOVING`), no casting, camera/cursor unchanged for N seconds | Max saver |
| **Flight path** | `UnitOnTaxi("player")`, `PLAYER_CONTROL_LOST/GAINED`, `TAXIMAP_CLOSED` | Max saver |
| **Background** | Client already has `maxFPSBk`; we just expose it in the UI | (CVar only) |
| **Resting / city** | `IsResting()`, `PLAYER_UPDATE_RESTING` | Off by default |
| **Vendor/AH/Mail/Bank open** | `AUCTION_HOUSE_SHOW/CLOSED`, `MAIL_SHOW`, `BANKFRAME_OPENED`… | Light saver, off by default |
| **Dead / ghost** | `UnitIsDeadOrGhost`, `PLAYER_DEAD`, `PLAYER_ALIVE`, `PLAYER_UNGHOST` | Off by default |
| **Cinematic / movie** | `CINEMATIC_START/STOP`, `PLAY_MOVIE` | Restore full |
| **Instance / raid** | `IsInInstance()`, `PLAYER_ENTERING_WORLD` | Optional "raid profile" (performance, not power) |

Engine behaviour:
- **Enter delay** (debounce) per situation, e.g. idle needs 120 s; taxi 2 s.
- **Exit is immediate** for "the player needs full graphics again" (combat, moved after idle).
- **Combat lockdown:** if a CVar change is blocked in combat, queue it and flush on `PLAYER_REGEN_ENABLED`. Combat itself always wants baseline, so normally the change was made *before* combat.

## 4. Graphics levers (CVars), ranked by power savings

1. `maxFPS` / `useMaxFPS` (foreground FPS cap): **the biggest power saving by far.** A 15–20 FPS cap on a flight path cuts GPU load dramatically. (`targetFPS` is a different setting, a minimum-FPS target, so we don't use it as a cap.)
2. `renderScale`: render resolution scale (e.g. 0.5).
3. Individual settings (**not** `graphicsQuality`: changing the preset overwrites the user's custom settings): `graphicsShadowQuality`, `graphicsSSAO`, `graphicsLiquidDetail`, `graphicsParticleDensity`, `graphicsSpellDensity`, `graphicsViewDistance`, `graphicsEnvironmentDetail`, `graphicsGroundClutter`, `graphicsComputeEffects`, `graphicsDepthEffects`, `graphicsOutlineMode`.
4. `ResampleQuality`, `ffxAntiAliasingMode`/`MSAAQuality`: avoid changing MSAA, since it can need a graphics restart.
5. `maxFPSBk`: background FPS cap (already built in; we'll expose it).

The CVarRegistry flags CVars that need `RestartGx()` / a client restart. **We never change those automatically.**
Exact CVar names must be confirmed on Forever with `/dump C_CVar.GetCVarInfo("name")`.

## 5. Libraries (fetched as externals, not committed; licences in `THIRD-PARTY-NOTICES.md`)

| Library | Purpose |
|---|---|
| LibStub, CallbackHandler-1.0 | Library loading / callbacks |
| AceAddon-3.0, AceEvent-3.0, AceTimer-3.0, AceConsole-3.0 | Addon skeleton, events, debounce timers, `/jpm` slash command |
| AceDB-3.0, AceDBOptions-3.0 | SavedVariables with profiles, plus a profile-management UI |
| AceConfig-3.0, AceConfigDialog-3.0, AceGUI-3.0 | Options UI registered into Blizzard's Settings panel |
| AceLocale-3.0 | Localization |
| *(none)* Blizzard Addon Compartment | Minimap menu entry (`## AddonCompartmentFunc`), built into Mainline/Forever |

LibDataBroker-1.1 is listed as "All Rights Reserved" (no licence in its repo), so it isn't used, and neither is
LibDBIcon-1.0, which depends on it. Mainline/Forever have the Blizzard Addon Compartment instead. For Classic
flavors without it, write our own small minimap button.

Ace3 is maintained for Mainline. Confirm it loads cleanly on Forever under the Midnight restrictions (it should, since it doesn't touch secret values).

## 6. Tooling and release
- **BigWigs packager** (`BigWigsMods/packager` GitHub Action) runs on tag push: fetches `.pkgmeta`
  externals, builds the zip, and optionally uploads to CurseForge / Wago / WoWInterface (needs API tokens as repo secrets).
- `scripts/fetch-libs.sh` gets Libs for local dev (via the packager's `-d -z` mode or plain `svn`/`git` checkouts).
- `scripts/link.sh` symlinks the repo into `World of Warcraft/_forever_/Interface/AddOns/JimPowerMizer` (check the folder name on your install).
- Lint: `luacheck` with WoW globals (`.luacheckrc`), run in CI.
- Version: `## Version: @project-version@` substituted by packager from git tags.

## 7. Milestones / actions

### M0: Repo and skeleton
- [x] `git init`, README, .gitignore, `.pkgmeta`, Forever TOC
- [x] License: BSD 3-Clause (`LICENSE`), third-party licences in `THIRD-PARTY-NOTICES.md`
- [x] Create GitHub repo and push, add the packager workflow
- [x] `scripts/fetch-libs.sh`, `scripts/link.sh`, `.luacheckrc`

### M1: Proof of concept (Forever only)
- [x] `Core/Init.lua` + `Compat/Mainline.lua`; flavor/build in `/jpm status` and `/jpm probe`
- [x] `Applier` with baseline snapshot + restore + crash recovery + combat deferral + respecting user edits
- [x] Engine (priority, enter delay, polling fallback) + Taxi situation + built-in "Max saver"/"Light saver" profiles
- [x] `/jpm status|on|off|restore|force|probe|debug`, addon-compartment click = status
- [x] Mock-API test harness (`tests/harness.lua`)
- [x] **In game:** `/jpm probe` write test passes (still to do: record CVar names/secure flags, out of and in combat)
- [x] **In game:** take a flight path; check FPS drops (`Ctrl+R` FPS display) and settings restore on landing
- [x] **In game:** `/reload` and log out mid-flight; check settings are right afterwards
- [x] Background FPS capped to the foreground cap; immediate re-apply after `/reload` on a flight path

### M2: Engine and situations
- [x] Situation plugin API + priority resolution + enter delays (+ `OnEvent`/`OnEnable` hooks)
- [x] Idle (AFK + inactivity timer), Combat, Cinematic, Resting, Dead, Service windows (AH/mail/bank/vendor)
- [x] `/jpm` commands: `status`, `on`, `off`, `restore`, `debug`, `list`, `enable`/`disable <situation>`, `idle <seconds>`
- [x] **In game:** idle (timeout and `/afk`), combat restores at once
- [x] Fixed: idle crashed in combat on secret values (`GetUnitSpeed`); Compat now treats secrets as unknown
- [x] **In game:** cursor movement outside the game while alt-tabbed does NOT count as activity, so idle keeps working in the background
- [x] **In game:** idle works; service window works at a mailbox
- [x] **In game:** bank works. Forever's bank is interaction type `CharacterBanker` (67); `BANKFRAME_OPENED/CLOSED` also fire
- [x] **In game:** no errors in combat after the secret-value fix

**M2 complete (2026-11-13).**

### M3: UI
- [x] AceConfig options (standalone window via `/jpm` + Settings > AddOns page): General, Situations, Graphics profiles, Settings profiles (AceDBOptions)
- [x] Per-situation enable/profile/priority/delay (+ idle timeout); profile editor with "Change" + value per CVar the client has
- [x] New profile (from your settings), rename, copy, delete, "Capture current" (uses your own values, not lowered ones)
- [x] Built-in profiles seeded once, so they can be edited/deleted for good; editing the active profile applies at once
- [x] Addon compartment: tooltip with situation + profile; left-click options, right-click on/off
- [x] Chat notification on switch (toggle)
- [x] **In game:** options window, Settings > AddOns page, compartment tooltip/clicks
- [x] **In game:** live edit of the active profile (drag Max saver's FPS slider during a flight)

**M3 complete.**
- [x] Keep `/console` tweaks: presets (e.g. `graphicsGroundClutter`) overwrite the CVars under them
  (e.g. `groundEffectDensity`). The Applier detects which CVars each batch of preset writes changed and
  restores their pre-saver values afterwards. Candidates: Graphics console category + known list (checked
  right after the writes and 0.5 s later), and the Default category (checked only *during* our writes,
  since it also holds unrelated CVars). Forever: `ConsoleGetAllCommands` (no `C_Console`); 184 Graphics
  CVars; `groundEffectDensity` is in Default (5). Option "Keep custom console settings" (default on).
- [x] **In game (2026-11-13):** Max saver's presets overwrote 31 lower-level CVars (ground effects, farclip/horizon,
  LOD distances, shadows, water, particles, SSAO, volume fog), all detected. On landing, the presets restored
  30 of them to the user's values by themselves; the custom `groundEffectDensity` (128; preset gives 48) was
  put back by the addon.
- [x] Friendly labels for enum values: dropdowns "3 - High" (game's localized `VIDEO_OPTIONS_*` strings) (M4)

### M4: Polish and release
- [x] Localization: AceLocale, English text as keys, `Locales/enUS.lua` generated by `scripts/gen-locale.py`
- [x] CI (`.github/workflows/ci.yml`): luacheck (0 warnings), locale check, mock-API tests
- [x] **v0.1.0 released (2026-11-13):** https://github.com/Vampyrbyte/JimPowerMizer/releases/tag/v0.1.0
  (`JimPowerMizer-v0.1.0-forever.zip`: libs, licences, version filled in, no dev files)
- [x] **In game:** `_Mainline` TOC loads on Forever; level-name dropdowns match the game's menu
- [x] **v0.1.1 (2026-11-14):** published to CurseForge (project 1803739), Wago (aND9V26o) and GitHub by the
  release workflow (secrets `CF_API_TOKEN`, `WAGO_API_TOKEN`; the workflow checks the CurseForge token first)

### After v0.1.1 (from play)
- [x] Idle: only your own movement (`PLAYER_STARTED/STOPPED_MOVING`) ends idle, so riding a transport doesn't;
  mouse/camera movement counts only with the new option "Mouse and camera movement count as activity" (default off)
- [x] **In game (2026-11-14):** idle stays active while riding the Deeprun Tram
- [x] Profile option "Hide the user interface" (`Core/Screen.lua`, profile key `hideUI`): `UIParent:Hide()`, not in
  combat lockdown or during cinematics; Alt+Z by the user wins until the next switch; nothing saved
- [x] Profile option "Hide names and nameplates" (key `hideNames`): sets every `UnitName*`/`nameplateShow*` CVar in
  `Registry.NAME_CVARS` that the client has to 0 through the Applier (baseline/restore/crash safety as usual; hidden
  from the editor; `/jpm probe` counts them)
- [ ] **In game:** names and nameplates disappear on a flight and come back on landing and for combat
- [x] Dimming: the game's `Brightness` CVar (0-100) as a normal profile setting. A black overlay was tried first but
  conflicted with hiding the UI; leftover `dim` keys are removed from saved profiles
- [ ] **In game:** UI hides and brightness drops on a flight and while idle; combat brings both back; Alt+Z while
  hidden; a cinematic during a hidden-UI flight; chat/minimap come back intact after landing
- [x] Max saver: particle density Low (was Fair); new registry CVars `graphicsLightMode` (Secondary Lighting, 0-3;
  also sets `giQuality`, `RenderFormat`) and `graphicsPBRLiquidDetail` (0-2; also sets `pbrLiquidDetail`), both 0 in
  Max saver. Names found in game with the new `/jpm watch`. Existing settings get built-in changes through
  `Database.BUILTIN_UPDATES` (only values still at the old built-in value)
- [ ] **In game:** Max saver lowers both; landing restores them and `giQuality`/`RenderFormat`/`pbrLiquidDetail`;
  level names for the two new dropdowns (currently plain numbers)

### M5: More flavors
- [ ] Midnight: add its interface to `JimPowerMizer_Mainline.toc` (`## Interface: 16001, 120105`), which should be nearly free
- [ ] `Compat/Classic.lua` + Classic TOCs; CVarRegistry availability per flavor

## 8. Risks / open questions
- ~~**CVar write restrictions on Forever/Midnight.**~~ Verified 2026-11-13: writes work in and out of combat.
- **Secret values (Midnight API).** Some unit data is secret, mostly in combat, and can't be compared. All reads go
  through the Compat layer, which turns secrets into "unknown"; the test harness simulates them.
- **Preset cascades.** Graphics presets reset the lower-level CVars under them. Handled by the detail snapshot;
  a `/console` change made *while* a saver profile is active is overwritten by the snapshot on restore.
- **Stutter on switching.** Changing some settings causes a hitch, so changes are batched and only made on situation transitions.
- **Interaction with Blizzard's own Settings UI.** If the user changes graphics while a saver profile is active, we must not "restore" over their change. Watch `CVAR_UPDATE` and update the baseline when the change wasn't ours.
- **Taxi detection edge cases:** dragonriding / skyriding "flight paths" and boat/zeppelin rides aren't `UnitOnTaxi`.
