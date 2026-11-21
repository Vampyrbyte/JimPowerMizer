# JimPowerMizer

A World of Warcraft addon that changes graphics settings automatically based on what you're doing,
for example dropping the frame-rate cap and render scale while you're AFK or on a flight path, and
restoring your normal settings the moment you need them (combat, moving again, etc.).

- **Supported (from 1.0.0):** WoW **Forever** (interface `16001`), **Midnight** (Standard, `120105`),
  **Classic Era** (`11509`, also Season of Discovery and Hardcore), **TBC Anniversary** (`20506`) and
  **Mists of Pandaria Classic** (`50504`). One download works in all of them:
  `JimPowerMizer_Mainline.toc` for Forever and Midnight, `JimPowerMizer_Classic.toc` for the Classic
  clients, and one compatibility layer (`Compat/`) for the differences.

See [docs/PLAN.md](docs/PLAN.md) for the architecture and roadmap.

## Development

```sh
scripts/fetch-libs.sh          # fetch LibStub + Ace3 into Libs/ (git-ignored)
scripts/link.sh [--forever | --retail | --classic-era | --anniversary | --classic]
                               # link as AddOns/JimPowerMizerDev in that client's folder (default _forever_)
luajit tests/harness.lua . [forever|midnight|classic_era|tbc_anniversary|mists_classic]
                               # mock-API tests as that client (default forever; CI runs all of tests/flavors)
scripts/gen-locale.py          # regenerate Locales/enUS.lua after adding L["..."] strings
```

The dev copy (`JimPowerMizerDev`, titled "JimPowerMizer (dev)") can sit next to the release
install (`JimPowerMizer`) with its own settings. Enable one at a time in the game's AddOns list and
reload. `link.sh` writes the dev TOCs (git-ignored) from the release TOCs, so run it again after a
TOC changes.

CI runs luacheck, the locale check and the tests (as every client) on every push. Pushing a tag like `v1.0.0`
from `main` builds a release zip with the libraries via the BigWigs packager, attaches it to a GitHub release
and uploads it to CurseForge and Wago for every client's game version. Each tag needs release notes in
`docs/releases/<tag>.md`.

## Translating

Copy `Locales/enUS.lua` to e.g. `Locales/deDE.lua`, change `"enUS", true, true` to `"deDE"`, remove
the last line (`ns.L = ...`), replace each `true` with the translation, and add the file to the TOC
after `Locales\enUS.lua`.

In game: `/jpm` opens the options (also in Settings > AddOns, and the minimap addon menu on Forever and Midnight); `/jpm help` lists commands;
`/jpm probe` checks which graphics settings the client exposes; `/jpm stats` shows the time and
energy each graphics profile has saved (enter your PC's power use on the options' Savings tab).

Libraries (LibStub, Ace3) are not committed. They're pulled in from `.pkgmeta`
by the [BigWigs packager](https://github.com/BigWigsMods/packager) when building a release.

## Licence

BSD 3-Clause, see [LICENSE](LICENSE). Embedded libraries keep their own licences, see
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
