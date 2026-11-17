# JimPowerMizer — Plan

Switch graphics settings automatically depending on what the player is doing,
to cut GPU/CPU power draw when full fidelity isn't needed (AFK, flight paths,
sitting in a city, alt-tabbed, etc.), and restore them when it is.

## 1. Target clients

| Flavor | Interface | TOC file | API family | Status |
|---|---|---|---|---|
| **Forever** | `16001` | `JimPowerMizer_Mainline.toc` | Mainline (Midnight 12.x API) | **Primary target** |
| Midnight (Standard) | `120105` (12.1.5) | `JimPowerMizer_Mainline.toc` | Mainline | **In progress** on the `midnight` branch (M5), first release 0.2.x |
| Mists / Cata / Wrath / TBC / Vanilla | `50504` / … / `11509` | `JimPowerMizer_Classic.toc` or per-flavor | Classic | Future |

**Verified on Forever build 1.60.1 (70938), 2026-11-13 (`/jpm probe`, out of combat):**
- Interface `16001`; `WOW_PROJECT_ID` = `WOW_PROJECT_CAMELOT` = `18`.
- All CVars in `Core/CVarRegistry.lua` exist under those names. None is secure, read-only or locked.
- Addon writes via `C_CVar.SetCVar` work (write test on `maxFPSBk` passed).
- In combat (`/jpm probe combat`, `InCombatLockdown()` true): the same flags, and the `maxFPSBk` write test
  also passes. So CVar writes aren't blocked by combat lockdown. Only `maxFPSBk` was write-tested; the
  combat deferral in the Applier stays as a safety net for any CVar the client marks secure.

**Verified on Midnight build 12.1.5 (70783), 2026-11-16 (`/jpm probe` and `/jpm probe combat`, branch `midnight`):**
- Interface `120105`; `WOW_PROJECT_ID` = `1`; `WOW_PROJECT_CAMELOT` is nil. Loads with compat Mainline.
- The CVars in `Core/CVarRegistry.lua` exist under the same names, except `graphicsPBRLiquidDetail` and
  `graphicsLightMode` (Forever only; the registry skips them). None is secure, read-only or locked.
- "Hide names": both clients have `nameplateShowFriendlyPlayers` and no `nameplateShowFriends` (Forever
  checked 2026-11-16). On both, writing `UnitNameEnemyMinionName` / `UnitNameFriendlyMinionName` makes the
  client set the matching pet, guardian and totem name CVars too; the Applier sets again what such a write
  changed (verified in game on both).
- Switch and restore work, including `/console` tweaks and hiding the UI, names and nameplates.
- The `maxFPSBk` write test passes out of combat and in combat, as on Forever.

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
| **Fishing** | Fishing pole in the main hand: `GetInventoryItemID("player", 16)` + `C_Item.GetItemInfoInstant` (class Weapon, subclass Fishing Pole), `PLAYER_EQUIPMENT_CHANGED` | Light saver |
| **Crafting** | Profession cast (`UnitCastingInfo`/`UnitChannelInfo` 6th value `isTradeSkill`, player `UNIT_SPELLCAST_*`), then a grace period (10 s) ended early by moving or `TRADE_SKILL_CLOSE`. The profession window alone doesn't count | Light saver |
| **Resting / city** | `IsResting()`, `PLAYER_UPDATE_RESTING` | Off by default |
| **Vendor/AH/Mail/Bank open** | `AUCTION_HOUSE_SHOW/CLOSED`, `MAIL_SHOW`, `BANKFRAME_OPENED`… | Light saver, off by default |
| **Dead / ghost** | `UnitIsDeadOrGhost`, `PLAYER_DEAD`, `PLAYER_ALIVE`, `PLAYER_UNGHOST` | Off by default |
| **Cinematic / movie** | `CINEMATIC_START/STOP`, `PLAY_MOVIE` | Restore full |
| **Dungeon / Raid / Battleground** (three situations; arenas count as battlegrounds) | `IsInInstance()` type `party` / `raid` / `pvp` or `arena`, `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA` | Lockout: your settings, priority 93 (above Idle, Long idle, Flight path), on. Scenarios and delves don't count |
| **Delve** (Midnight/Standard only) | `IsInInstance()` type `scenario` with `GetInstanceInfo()` difficulty 208, or `C_PartyInfo.IsDelveInProgress()` | Same lockout. Other scenarios don't count |

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
- `scripts/link.sh` symlinks the repo into `World of Warcraft/_forever_/Interface/AddOns/JimPowerMizerDev` (with a generated, git-ignored `JimPowerMizerDev_Mainline.toc`), so it can sit next to the release install in `AddOns/JimPowerMizer`.
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

### v0.1.2 (from play)
- [x] Idle: only your own movement (`PLAYER_STARTED/STOPPED_MOVING`) ends idle, so riding a transport doesn't;
  mouse/camera movement counts only with the new option "Mouse and camera movement count as activity" (default off)
- [x] **In game (2026-11-14):** idle stays active while riding the Deeprun Tram
- [x] Profile option "Hide the user interface" (`Core/Screen.lua`, profile key `hideUI`): `UIParent:Hide()`, not in
  combat lockdown or during cinematics; Alt+Z by the user wins until the next switch; nothing saved
- [x] Profile option "Hide names and nameplates" (key `hideNames`): sets every `UnitName*`/`nameplateShow*` CVar in
  `Registry.NAME_CVARS` that the client has to 0 through the Applier (baseline/restore/crash safety as usual; hidden
  from the editor; `/jpm probe` counts them)
- [x] **In game (2026-11-14):** names and nameplates disappear on a flight and come back on landing and for combat
- [x] Built-in "Cinematic" profile: hide UI + names/nameplates, 30 FPS cap, graphics left at your settings (screensaver
  feel). Not assigned to a situation by default; added to existing settings by `BUILTIN_UPDATES` (now `change`/`add`)
- [x] **In game (2026-11-14):** Cinematic profile assigned to idle or taxi
- [x] Situation "Cinematic" shown as "Cutscenes" (key stays `cinematic`; `cutscenes` accepted in commands)
- [x] Dimming: the game's `Brightness` CVar (0-100) as a normal profile setting. A black overlay was tried first but
  conflicted with hiding the UI; leftover `dim` keys are removed from saved profiles
- [x] **In game (2026-11-14):** UI hides and brightness drops on a flight and while idle; combat brings both back; Alt+Z while
  hidden; a cinematic during a hidden-UI flight; chat/minimap come back intact after landing
- [x] Max saver: particle density Low (was Fair); new registry CVars `graphicsLightMode` (Secondary Lighting, 0-3;
  also sets `giQuality`, `RenderFormat`) and `graphicsPBRLiquidDetail` (0-2; also sets `pbrLiquidDetail`), both 0 in
  Max saver. Names found in game with the new `/jpm watch`. Existing settings get built-in changes through
  `Database.BUILTIN_UPDATES` (only values still at the old built-in value)
- [x] **In game (2026-11-14):** Max saver lowers both; landing restores them and `giQuality`/`RenderFormat`/`pbrLiquidDetail`
- [ ] Level names for Secondary Lighting / PBR liquid dropdowns (currently plain numbers; need the menu's labels)
- [x] **v0.1.2 (2026-11-14):** tagged; released by the workflow

### v0.1.3 (from play)
- [x] Situation "Fishing": a fishing pole in the main hand (Forever: you hold the pole; verified item 12225 in
  slot 16, profession tool slots 28/29 empty). Light saver, priority 55, delay 1 s. Each cast counts as input for Idle
- [x] Situation "Crafting": a profession cast (`isTradeSkill`, verified true for Smelt Copper and false for Fishing),
  then `grace` seconds (default 10, option and `/jpm crafting <seconds>`) ended early by moving or by closing the
  profession window if it was open during the craft. Light saver, priority 50
- [x] **In game (2026-11-14):** fishing pole on/off switches; a Craft All run stays on Light saver between casts; grace ends on
  moving and on closing the window; browsing the profession window while moving doesn't switch
- [x] **v0.1.3 (2026-11-14):** tagged; released by the workflow

### Energy savings (next 0.1.x, from `main`)

Goal: show how much energy each graphics profile has saved, from the time it was active and the power
figures the user enters. Decided 2026-11-16: no power is measured or estimated by the addon (there is no
API); account-wide only; cost and CO₂ optional; nothing is shown for figures the user hasn't entered.

**Data** (`db.global.savings`, account-wide, so switching settings profiles or characters keeps it)
```lua
savings = {
  normal   = nil,                  -- PC power (W) at your own settings
  watts    = { ["Max saver"] = nil, ... }, -- PC power (W) with each profile applied
  price    = nil, currency = nil,  -- price per kWh and a symbol, e.g. 0.25 and "£"
  co2      = nil,                  -- grams of CO₂ per kWh (from your supplier or country)
  stats    = { ["Max saver"] = { seconds = 0 }, ... },
  deleted  = { seconds = 0, wh = 0 },  -- all deleted profiles together, energy fixed at deletion
  since    = nil,                  -- time() of the first record or the last reset
}
```
- Only time is recorded. Energy is worked out when shown: `seconds / 3600 × (normal − profile W)` Wh. So
  watts entered later count for all the time already recorded; a profile at or above the normal watts
  shows no saving.
- Session totals are kept in memory only.

**Recording** (`Core/Savings.lua`, called by the Applier where `state.active` changes)
- [x] On every change of the applied profile, add the time since it started to the outgoing profile; start
  the clock for the new one. "Your own settings" isn't counted.
- [x] Stop on restore, on disable and on `PLAYER_LOGOUT`; start at login if a profile is still applied
  (crash recovery). A crash loses the time since the last logout (SavedVariables aren't written).
- [x] Renaming a graphics profile moves its stats and watts. Deleting one moves its time, and its energy
  worked out with its watts at that moment, into `deleted`, and removes its entry and watts; the totals
  still include it, shown as one "Deleted profiles" line. A new profile (or a rename) that reuses the name
  starts from zero, never adopting the old stats (decided 2026-11-16).

**Output** (each part only when its figures are entered; no "n/a" or empty columns)
- [x] `/jpm stats`: per profile, time; plus energy if `normal` and that profile's watts are set; plus cost if
  a price is set; plus CO₂ if a factor is set. Session and lifetime totals. With no watts entered at all,
  one line saying where to enter them. `/jpm stats reset` (asks to confirm).
- [x] Chat line when a profile ends, only if "Chat message when switching" is on **and** that profile's
  energy can be worked out; added to the existing switch message, e.g. "Restored your graphics settings
  (combat). Max saver: 22 min, ~45 Wh saved (~£0.01, ~12 g CO₂)". Otherwise the message is unchanged.
- [x] Options, a "Savings" tab: watts at your own settings and per graphics profile; price and currency
  symbol; CO₂ factor; the stats table; reset button. Help text: measure at the wall (a plug-in meter) if
  possible; GPU software only reads the GPU, so use the same method for every figure; measure with the
  game in the foreground; the background FPS limit note (see below).
- [x] Units: Wh below 1 kWh (1 decimal below 10 Wh), else kWh to 2 places; g below 1 kg, else kg; cost to 2 places.

**Tests**
- [x] Harness (every flavor): time across switches with `advance()`, logout and restore; energy from
  watts entered later; output leaves out each missing part; no chat line with notify off or no watts;
  rename moves stats. Built 2026-11-16 (harness session 10, both flavors).
- [x] In game on Forever (logged in `notes/TESTING.md`): switch, `/jpm stats`, options tab, chat line.
  Passed 2026-11-16. Released in v0.1.5 (Forever) and v0.2.0-beta2 (Forever and Midnight); merged into
  `classic` (its TOC lists `Core\Savings.lua` too).

**Known limits:** savings are only as good as the watts entered; time with the game in the background
counts the same as in the foreground (the background cap may already have saved some of it).

**Background:** not detected (decided 2026-11-16). There is no window focus API; the frame rate
can't tell front from back while a profile caps both the same, and the workarounds are too hacky. The
help text on the Savings tab says so instead: while the game's background FPS limit is in force (e.g.
alt-tabbed), the savings shown may be wrong, as the addon can't reliably account for it.

### M5: More flavors

#### Midnight (Standard)
Goal: **one package for Forever and Midnight**, first released as 0.2.x. Forever-only releases stay 0.1.x
from `main` until the merge.

**How the work is organized**
- Branch `midnight`, in its own worktree (`../JimPowerMizer-midnight`). Each game's dev copy is linked to
  its own checkout: `_forever_` → main checkout, `_retail_` → midnight worktree (`scripts/link.sh --forever`
  / `--retail`, run from the checkout to link). No `git checkout` needed to switch between Forever fixes
  and Midnight work.
- Forever fixes and features go to `main` (released as 0.1.x) and are merged into `midnight` (merge, not
  rebase). Changes that don't depend on the client go to `main` first.
- CI runs on pushes to `main` and `midnight`. The release workflow runs the same checks first, and
  `scripts/check-release-tag.sh` only releases stable tags from `main` and alpha/beta tags that include
  all of `main`.

**Forever must keep working at every step** (betas go to both clients):
- Shared code (Core, Situations, Options) is the same for both clients; differences between the games
  live in `Compat`, chosen by interface number (16001 vs 12xxxx), never by `WOW_PROJECT_ID`.
- The harness runs every shared test for both clients (`tests/harness.lua . forever|midnight`), and CI
  runs both. Each Midnight change has a Forever check that its behavior is unchanged.
- New CVars and events must be safe where they don't exist (the registry skips missing CVars; optional
  events are registered with `pcall`).
- Before each beta: merge `main`, then a short Forever smoke test (load with `/jpm debug`, force idle and
  back, a flight, the fishing pole), recorded in the test log.

**Steps**
- [x] Phase 0: `link.sh --forever/--retail`; CI on `midnight`; release runs the checks; tag guard
- [x] Harness flavors (`forever`, `midnight`), CI runs both (on `main`)
- [x] Phase 1, in game on Midnight (2026-11-16): loads, probe in and out of combat, switch and restore, hide UI
  and names/nameplates; results in §1. Forever loads the two-interface TOC (`16001, 120105`) as before
- [ ] Phase 2 (one commit each, both clients pass):
  - [x] Fishing: Forever keeps "pole in the main hand"; Midnight (pole in a profession slot) counts
    channeling Fishing (spell 131476, or any channel with that spell's name), then `fishing.grace` seconds
    (default 10, an option on Midnight only), ended early by moving. Chosen by `Compat:FishesByChannel()`
  - [x] **In game (2026-11-16, Midnight):** fishing casts switch to Light saver and stay there between casts;
    the grace period ends after 10 s or on moving
  - [x] Service windows: no change needed. **In game (2026-11-16, Midnight 12.1.5):** bank `Banker` (8),
    mail `MailInfo` (17), vendor `Merchant` (5), auction house `Auctioneer` (21); each also fires its older
    window event, and every one starts and ends the situation. `AccountBanker` (warband bank from a
    distance) is mapped but not seen yet
  - [x] Crafting orders (from Blizzard's API documentation; the user's account can't open them): placing
    orders (`ProfessionsCustomerOrder` (60), `CRAFTINGORDERS_SHOW/HIDE_CUSTOMER`) is a service window; the
    orders you fill at a crafting table (`CRAFTINGORDERS_SHOW/HIDE_CRAFTER`) count as the profession window
  - [ ] **In game (Midnight), by someone who can open crafting orders:** `/jpm debug` lines for both windows
  - [x] Graphics: nothing to add (2026-11-16). `graphicsComputeEffects` is already in the registry, and the
    user's Midnight menu has no upscaling beyond Forever's (FSR 1 only; no DLSS, FSR 3/4 or XeSS)
  - [ ] Parked (2026-11-16): ray-traced shadows (turned off by Blizzard in 12.1.5) and variable rate shading
    (refused with "not a Shader Model 6 card" although `gxApi` is D3D12; maybe turned off with ray tracing).
    Revisit when ray tracing is back
  - [x] Combat: writes work in lockdown (`/jpm probe combat`, 2026-11-16); the combat deferral covers secure CVars
  - [x] Secret values: no errors in a long open-world fight (2026-11-16, target dummy)
  - [x] Secret values in a dungeon: no errors (2026-11-17, a dungeon run on Midnight)
  - [x] Typing and interface clicks keep you active; panning the camera doesn't (2026-11-16)
- [x] Packaging: the BigWigs packager takes `_Mainline` with `## Interface: 16001, 120105` as one file for
  Forever and Retail ("multi-version", game versions 12.1.5 and 1.60.1); no separate TOCs needed
- [x] Store pages: nothing to enable. CurseForge and Wago take the game versions and the release type per file,
  and the packager sets both (from the TOC and the tag name). README mentions Midnight (on `midnight`)
- [ ] Betas `v0.2.0-betaN` from `midnight` (tagged only when asked), for both clients; check each site's
  Files page shows type Beta. If the sites mishandle it, archive the file and keep testing private
  - [x] **v0.2.0-beta1 (2026-11-16):** from `midnight` at `2878360`. Uploaded to CurseForge and Wago as beta
    for 12.1.5 and 1.60.1; GitHub pre-release. Still to check: each site's Files page
  - [x] **v0.2.0-beta2 (2026-11-16):** from `midnight`, adds energy savings (as in v0.1.5)
  - [ ] Feedback wanted: crafting orders windows (dungeons checked by the user 2026-11-17)
- [ ] Merge into `main`, retest Forever, release `v0.2.0`. After that, each Midnight patch needs its
  interface number added to the TOC

#### Later
- [x] Instances (asked for 2026-11-16, all clients; built 2026-11-17 on `main`, next 0.1.x): three
  situations, Dungeon (`party`), Raid (`raid`) and Battleground (`pvp` and `arena`), on by default as a
  lockout: profile "your settings", priority 93 (above Idle 90, Flight path 91 and Long idle 92; below
  Cutscenes and Combat), so nothing switches inside and no settings change can cause a hitch. Each can get
  a profile of its own instead. Scenarios and delves aren't included (story scenarios should still go
  idle). `Compat:GetInstanceType()`; `/jpm debug` prints the instance type on each change
  - [x] **In game (Forever, 2026-11-17):** listed at priority 93; a dungeon keeps your settings while
    idle. Raid, battleground and arena not tried yet (same code path, different instance type)
  - [x] Delve (2026-11-17, on `midnight`; Forever and Classic have no delves): its own situation, same
    lockout defaults. Only on clients with delves (`Compat:HasDelves()`, interface 11.0+); situations
    can say they aren't available (`IsAvailable`), and are then dropped and never shown. A delve is
    instance type `scenario` with difficulty 208, or `C_PartyInfo.IsDelveInProgress()` (from Blizzard's
    API documentation); `/jpm debug` prints each scenario's difficulty
  - [x] **In game (Midnight, 2026-11-17):** listed with Delve at priority 93; a dungeon keeps your settings
  - [ ] **In game (Midnight):** a delve: "Scenario difficulty 208: a delve", lockout while idle
- [ ] Classic: see M6

### M6: Classic (0.3.x)

Goal: one package for Forever, Midnight and the Classic clients, first released as `v0.3.0-betaN` from a
`classic` branch. Meanwhile 0.1.x stays the stable release from `main` and 0.2.0 betas continue from
`midnight`. Everything ends up on `main` as one version.

**Which clients.** Every Classic client Blizzard runs (decided 2026-11-16). Known now: Classic Era 1.15.9
(`_classic_era_`, installed; Season of Discovery and Hardcore realms are played on this same client), TBC
Anniversary and Mists of Pandaria Classic (the user will install both). Phase 0 confirms the list, each
client's folder and interface number.

**Branches while betas overlap**

| Branch | Folder | Releases | Contains |
|---|---|---|---|
| `main` | `~/repos/JimPowerMizer` | 0.1.x stable (Forever) | Forever |
| `midnight` | `~/repos/JimPowerMizer-midnight` | `v0.2.0-betaN` | `main` + Midnight |
| `classic` | `~/repos/JimPowerMizer-classic` | `v0.3.0-betaN` | `midnight` + Classic |

- Merges flow one way while betas run: `main` → `midnight` → `classic` (merge, not rebase). Nothing goes
  back up until a branch is finished.
- Where a change goes: works on every client → `main` (named as such: it ships in the next 0.1.x);
  Midnight only → `midnight`; Classic only → `classic`. Then merge it down the chain the same day.
- **Docs live on `main` only** (decided 2026-11-16): `docs/` and `README.md` are edited on `main` and
  reach the other branches by the usual merge down. They aren't packaged, so this never changes a
  release. The split branches are meant to be short-lived; after the merge, back to one branch.
- Parallel work: one Claude session per folder. Each game's dev copy is linked to the folder whose
  code it should run (`scripts/link.sh`).
- Tag guard: stable tags only from `main` (unchanged); a `v0.3.0` pre-release must include all of `main`
  and of `midnight` while `midnight` is unmerged, and (while 0.2.0 isn't stable) its package must not
  include `JimPowerMizer_Mainline.toc`.

**Two beta lines at once** (decided 2026-11-16: run them side by side, so a fix can be tested in one
without affecting the other's players).
- While 0.2.0 isn't stable, each line goes to its own clients: `v0.2.0-betaN` (from `midnight`) to Forever
  and Midnight, `v0.3.0-betaN` (from `classic`) to the Classic clients only. Neither can overtake the
  other, since they never share a game version.
- 0.3 packages leave out `JimPowerMizer_Mainline.toc` (an `ignore` line in `.pkgmeta`, on `classic` only).
  The packager would still label them with every TOC's game versions, so the release workflow passes
  `-g` with only the packaged TOCs' versions (`scripts/package-args.sh`; dry run on `classic`: 1.15.9
  only). The `ignore` line is removed once 0.2.0 is stable; from then on 0.3 betas go to every client.
- A Midnight fix ships to Forever and Midnight beta players in the next 0.2 beta. It reaches Classic
  players only in a later 0.3 beta, after the Classic tests. A Classic fix never reaches 0.2 players.
- Still merged down the chain (`main` → `midnight` → `classic`), so the final merges stay small.

**Steps**
- [x] Phase 0 (no game needed, except reading interface numbers; done 2026-11-17):
  - [x] The live Classic clients and folders (all installed 2026-11-17): Classic Era 1.15.9.70576 in
    `_classic_era_` (also Season of Discovery and Hardcore), TBC Anniversary 2.5.6.70577 in `_anniversary_`,
    Mists of Pandaria Classic 5.5.4.70631 in `_classic_` (versions from `.build.info`). Interface numbers
    11509, 20506, 50504, following the version as other addons' TOCs do (Questie's Mists TOC: 50504).
    One `_Classic` TOC lists all three. Still to confirm in game (Phase 1): `/dump select(4, GetBuildInfo())`,
    and that each client reads `_Classic` (else per-client `_Vanilla` / `_TBC` / `_Mists`)
  - [x] Branch `classic` from `midnight`, worktree `~/repos/JimPowerMizer-classic` (2026-11-16);
    `link.sh --classic-era`, `--anniversary`, `--classic` (a dev TOC per release TOC); all three Classic
    dev copies linked to `classic`
  - [x] CI on `classic`; each branch lists its client flavors in `tests/flavors`; tag guard for 0.3
    (includes `main` and `midnight`; Classic-only while 0.2 isn't stable); game versions from the
    packaged TOCs only (`-g 1.15.9,2.5.6,5.5.4`)
  - [x] Harness flavors `classic_era`, `tbc_anniversary`, `mists_classic` (the mock still behaves like
    Mainline until the in-game probe)
  - [x] `JimPowerMizer_Classic.toc` (same file list, `## Interface: 11509, 20506, 50504`). Compat: the
    existing Mainline code passes the harness on all three and picks the held-pole fishing rule and no
    delves by interface; what Classic really lacks comes from the Phase 1 probe
- [ ] Phase 1, in game on each Classic client (Era, TBC Anniversary, Mists Classic; SoD and Hardcore get a
  short load-and-switch check on Era's client): loads without errors and isn't out of date; `/jpm probe`
  and `/jpm probe combat`; switch and restore incl. `/console` tweaks; hide UI and names/nameplates;
  options window and Settings page; addon compartment (may not exist: `/jpm` still opens options)
- [ ] Phase 2 (one commit each, every client passes):
  - [ ] Graphics: which registry CVars exist (Classic's menu is smaller), preset cascades, `/jpm watch`
    for anything Classic has that the others don't
  - [ ] Situations: Taxi, Idle input (typing, interface clicks), Combat, Cutscenes, Resting, Dead
  - [ ] Service windows: interaction types vs the older window events on each client
  - [ ] Fishing: pole in the main hand, as on Forever (expected)
  - [ ] Crafting: `isTradeSkill`; Era may use separate Craft window events for some professions
  - [ ] Secret values: not expected on Classic (already optional in Compat)
- [ ] Packaging: dry run on `classic` with the `.pkgmeta` ignore line: only the `_Classic` TOC packaged, game
  versions only Classic ones; check CurseForge and Wago list each Classic client. Later, a dry run with
  both TOCs (after 0.2.0)
- [ ] Betas `v0.3.0-betaN` from `classic` (tagged only when asked), Classic clients only. Before each:
  merge `midnight`, run the Classic tests. Forever/Midnight smoke tests only once 0.3 packages include them
- [ ] Finish: merge `midnight` into `main`, release 0.2.0; merge `main` into `classic` and drop the
  `.pkgmeta` ignore line (0.3 betas now go to every client, with Forever and Midnight smoke tests); when
  Classic feedback is good, merge `classic` into `main` and release 0.3.0. Then one branch again; remove the
  worktrees. Each Classic patch then needs its interface number added, like Midnight's

## 8. Risks / open questions
- ~~**CVar write restrictions on Forever/Midnight.**~~ Verified 2026-11-13: writes work in and out of combat.
- **Secret values (Midnight API).** Some unit data is secret, mostly in combat, and can't be compared. All reads go
  through the Compat layer, which turns secrets into "unknown"; the test harness simulates them.
- **Preset cascades.** Graphics presets reset the lower-level CVars under them. Handled by the detail snapshot;
  a `/console` change made *while* a saver profile is active is overwritten by the snapshot on restore.
  Switches less than 0.5 s apart (fixed 2026-11-17): a cascade can land after the next switch (e.g. a
  restore 0.2 s after a saver started, before the saver's delayed check saw `farclip` follow View
  Distance). Such switches are checked as one, against the values from before the first of them, and a
  saver period starting within 0.5 s of a restore continues the earlier period's originals (verified on
  Forever 2026-11-17: a macro with `/jpm force idle` and `/jpm force off`, clicked repeatedly, kept the
  `/console farclip` value)
- **Stutter on switching.** Changing some settings causes a hitch, so changes are batched and only made on situation transitions.
- **Interaction with Blizzard's own Settings UI.** If the user changes graphics while a saver profile is active, we must not "restore" over their change. Watch `CVAR_UPDATE` and update the baseline when the change wasn't ours.
- **Three branches, two beta lines (M6).** More merging and more release steps. The one-way merge rule
  and the tag guard keep releases from missing fixes; separate game versions keep the beta lines apart.
  If 0.2.0 takes long, 0.3 stays Classic-only for as long.
- **Classic test coverage.** Each Classic client has to be installed and tested; interface numbers change
  with Classic patches as with Midnight.
- **Taxi detection edge cases:** dragonriding / skyriding "flight paths" and boat/zeppelin rides aren't `UnitOnTaxi`.
