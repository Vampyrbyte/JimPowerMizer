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
| **Cinematics** | Always your own settings |
| **Idle / AFK** | *Max saver* after 3 minutes without input, or 5 seconds after `/afk` |
| **Flight path** | *Max saver* |
| Dead / ghost | Off by default |
| Auction house / mail / bank / vendor | Off by default |
| Resting (inn / city) | Off by default |

Each situation has its own graphics profile, priority and delay. Idle keeps saving while you're alt-tabbed.

### Graphics profiles
- Built-in **Max saver** (20 FPS, half render scale, low shadows/particles/effects/view distance) and **Light saver** (30 FPS, lighter shadows).
- Create your own: start from your current settings, then tick only the settings you want changed.
- When a profile caps foreground FPS, your background FPS cap is lowered to match, so alt-tabbing doesn't *raise* the frame rate.
- Optionally **hide the UI** (like Alt+Z) and **dim the screen** while a profile is active, e.g. on long flights or while idle. Both undo themselves for combat.

### Your settings are safe
- Your own values are saved before anything changes and restored afterwards, including after a `/reload`, logout or crash.
- Change a setting yourself while a saver profile is active and your change is kept.
- **Custom `/console` tweaks survive**: graphics presets normally reset the settings under them (e.g. `groundEffectDensity`); JimPowerMizer detects that and puts your values back.

### Usage
- `/jpm` opens the options (also in *Settings > AddOns* and the minimap addon menu).
- Minimap addon menu: hover for status, left-click for options, right-click to turn switching on/off.
- `/jpm help` lists all commands.

Currently for **WoW Forever**. Other game versions are planned.
