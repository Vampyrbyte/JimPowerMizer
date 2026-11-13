# JimPowerMizer — Plan

Switch graphics settings automatically depending on what the player is doing,
to cut GPU/CPU power draw when full fidelity isn't needed (AFK, flight paths,
sitting in a city, alt-tabbed, etc.), and restore them when it is.

## 1. Target clients

| Flavor | Interface | TOC file | API family | Status |
|---|---|---|---|---|
| **Forever** | `16001` | `JimPowerMizer_Forever.toc` | Mainline (Midnight 12.x API) | **Primary target** |
| Midnight (Standard) | `120105` | `JimPowerMizer_Mainline.toc` | Mainline | Future (easy, same API) |
| Mists / Cata / Wrath / TBC / Vanilla | `50504` / … / `11509` | `JimPowerMizer_Classic.toc` or per-flavor | Classic | Future |

**Verified on Forever build 1.60.1 (70938), 2026-11-13 (`/jpm probe`, out of combat):**
- Interface `16001`; `WOW_PROJECT_ID` = `WOW_PROJECT_CAMELOT` = `18`.
- All CVars in `Core/CVarRegistry.lua` exist under those names. None is secure, read-only or locked.
- Addon writes via `C_CVar.SetCVar` work (write test on `maxFPSBk` passed).
- In combat (`/jpm probe combat`, `InCombatLockdown()` true): the same flags, and the `maxFPSBk` write test
  also passes. So CVar writes aren't blocked by combat lockdown. Only `maxFPSBk` was write-tested; the
  combat deferral in the Applier stays as a safety net for any CVar the client marks secure.

Notes / things to verify in the live client (sources are beta-era fan sites + Warcraft Wiki):
- `/dump select(4, GetBuildInfo())` → expect `16001`.
- `/dump WOW_PROJECT_ID, WOW_PROJECT_CAMELOT` → `WOW_PROJECT_ID` was reported as `1` on one beta build and `18` (`WOW_PROJECT_CAMELOT`) on a later one. **Don't branch on project ID alone**; check for the specific APIs we use.
- Midnight addon restrictions ("secret values", combat lockdown) apply on Forever. Confirm which graphics CVars can be set by `SetCVar` from addon code, and whether they're blocked in combat.

## 2. Architecture

```
JimPowerMizer/
├── JimPowerMizer_Forever.toc      # per-flavor TOCs, each lists the shared files + its Compat file
├── JimPowerMizer_Mainline.toc     # (later)
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
- [ ] Situation plugin API + priority resolution + enter delays
- [ ] Idle (AFK + custom inactivity timer), Combat, Resting, Dead, Cinematic, Vendor windows
- [ ] `/jpm` commands: `status`, `on`, `off`, `restore`, `debug`

### M3: UI
- [ ] AceConfig options: per-situation enable/profile/priority/delay; profile editor (only CVars the client has, with sliders/dropdowns from CVarRegistry)
- [ ] "Capture current settings as profile" button
- [ ] Addon compartment entry with tooltip: active situation, active profile, current FPS cap
- [ ] Optional chat/screen notification on switch

### M4: Polish and release
- [ ] Localization scaffolding, luacheck clean, CI
- [ ] Tag `v0.1.0`, publish to CurseForge (Forever flavor) / Wago

### M5: More flavors
- [ ] `JimPowerMizer_Mainline.toc` (Midnight), which should be nearly free
- [ ] `Compat/Classic.lua` + Classic TOCs; CVarRegistry availability per flavor

## 8. Risks / open questions
- ~~**CVar write restrictions on Forever/Midnight.**~~ Verified 2026-11-13: writes work in and out of combat.
- **Stutter on switching.** Changing some settings causes a hitch, so changes are batched and only made on situation transitions.
- **Interaction with Blizzard's own Settings UI.** If the user changes graphics while a saver profile is active, we must not "restore" over their change. Watch `CVAR_UPDATE` and update the baseline when the change wasn't ours.
- **Taxi detection edge cases:** dragonriding / skyriding "flight paths" and boat/zeppelin rides aren't `UnitOnTaxi`.
