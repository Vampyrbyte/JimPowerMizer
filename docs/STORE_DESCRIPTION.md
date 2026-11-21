# Store listing (CurseForge / Wago)

**Name:** JimPowerMizer

**Summary (one line):** Automatically lowers graphics settings when you don't need them (idle, AFK, flight paths) to save power, and restores yours the moment you do.

**Categories:** Miscellaneous; Data Broker / Minimap (if offered)

**License:** BSD 3-Clause

**Source:** https://github.com/Vampyrbyte/JimPowerMizer
**Issues:** https://github.com/Vampyrbyte/JimPowerMizer/issues

---

## Description

JimPowerMizer switches your graphics settings automatically depending on what you're doing, so your PC
or laptop isn't rendering at full detail while you're AFK, on a flight path or sitting at the auction
house. Less power, less heat, less fan noise, and your normal settings come back the moment you need them.

### Situations
| Situation | Default |
|---|---|
| **Combat** | Always your own settings, restored the instant a fight starts |
| **Cutscenes** | Always your own settings |
| **Idle / AFK** | *Max saver* after 3 minutes without input, or 5 seconds after `/afk` |
| **Long idle** | *Max saver* after 15 minutes without input; give it its own profile (e.g. *Cinematic*, or *Light saver* for short idle) |
| **Flight path** | *Max saver*, until you do something after landing |
| **Dungeon / Raid / Battleground** (and **Delve** on Midnight) | Your own settings: nothing switches inside an instance, not even when you're idle (arenas count as battlegrounds) |
| **Fishing** | *Light saver* while a fishing pole is in your main hand (on Midnight: while you fish, and for 10 seconds after) |
| **Crafting** | *Light saver* while you craft, and for 10 seconds after (moving or closing the profession window ends it sooner) |
| Dead / ghost | Off by default |
| Auction house / mail / bank / vendor | Off by default |
| Resting (inn / city) | Off by default |

Each situation has its own graphics profile, priority and delay. Idle keeps saving while you're alt-tabbed.

### Graphics profiles
- Built-in **Max saver** (20 FPS, half render scale, low shadows/particles/effects/view distance), **Light saver** (30 FPS, lighter shadows) and **Cinematic** (your own graphics with the UI, names and nameplates hidden and the frame rate capped: a cozy screensaver for idle time or long flights).
- Every setting your game's own Graphics menu has, with the game's names for each level: shadows, liquids, particles, SSAO, depth and compute effects, outlines, sun shafts, textures, spell density, view distance, anti-aliasing (incl. multisample), texture filtering and more. Each client shows the ones it has.
- Create your own: start from your current settings, then tick only the settings you want changed.
- Changed a built-in profile? **Reset to defaults** puts it back. Deleted one? **Restore a built-in profile** brings it back.
- When a profile caps foreground FPS, your background FPS cap is lowered to match, so alt-tabbing doesn't *raise* the frame rate.
- Optionally **hide the UI** (like Alt+Z), **names and nameplates**, and turn the **brightness** down while a profile is active, e.g. on long flights or while idle. Both come back for combat.

### Your settings are safe
- Your own values are saved before anything changes and restored afterwards, including after a `/reload`, logout or crash.
- Change a setting yourself while a saver profile is active and your change is kept.
- **Custom `/console` tweaks survive**: graphics presets normally reset the settings under them (e.g. `groundEffectDensity`); JimPowerMizer detects that and puts your values back.

### Usage
- `/jpm` opens the options (also in *Settings > AddOns*, and the minimap addon menu on Forever and Midnight).
- Minimap addon menu (Forever and Midnight): hover for status, left-click for options, right-click to turn switching on/off.
- `/jpm help` lists all commands.

### Game versions
One download for **WoW Forever**, **Midnight** (Standard), **Classic Era** (including Season of Discovery and Hardcore), **TBC Anniversary** and **Mists of Pandaria Classic**.
