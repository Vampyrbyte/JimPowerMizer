# JimPowerMizer

A World of Warcraft addon that changes graphics settings automatically based on what you're doing,
for example dropping the frame-rate cap and render scale while you're AFK or on a flight path, and
restoring your normal settings the moment you need them (combat, moving again, etc.).

- **Primary target:** WoW **Forever** (interface `16001`)
- **Planned:** Midnight (Standard) and the Classic flavors, via a per-flavor compatibility layer

See [docs/PLAN.md](docs/PLAN.md) for the architecture and roadmap.

## Development

```sh
scripts/fetch-libs.sh          # fetch LibStub + Ace3 into Libs/ (git-ignored)
scripts/link.sh [game_dir]     # symlink into <game_dir>/Interface/AddOns (defaults to the _forever_ folder)
luajit tests/harness.lua .     # run the mock-API tests
scripts/gen-locale.py          # regenerate Locales/enUS.lua after adding L["..."] strings
```

CI runs luacheck, the locale check and the tests on every push. Pushing a tag like `v0.2.0` builds
a release zip with the libraries via the BigWigs packager and attaches it to a GitHub release.

## Translating

Copy `Locales/enUS.lua` to e.g. `Locales/deDE.lua`, change `"enUS", true, true` to `"deDE"`, remove
the last line (`ns.L = ...`), replace each `true` with the translation, and add the file to the TOC
after `Locales\enUS.lua`.

In game: `/jpm` opens the options (also in Settings > AddOns and the minimap addon menu); `/jpm help` lists commands;
`/jpm probe` checks which graphics settings the client exposes.

Libraries (LibStub, Ace3) are not committed. They're pulled in from `.pkgmeta`
by the [BigWigs packager](https://github.com/BigWigsMods/packager) when building a release.

## Licence

BSD 3-Clause, see [LICENSE](LICENSE). Embedded libraries keep their own licences, see
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
