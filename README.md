# JimPowerMizer

A World of Warcraft addon that changes graphics settings automatically based on what you're doing,
for example dropping the frame-rate cap and render scale while you're AFK or on a flight path, and
restoring your normal settings the moment you need them (combat, moving again, etc.).

- **Primary target:** WoW **Forever** (interface `16001`)
- **Planned:** Midnight (Standard) and the Classic flavors, via a per-flavor compatibility layer

See [docs/PLAN.md](docs/PLAN.md) for the architecture and roadmap.

## Development

Libraries (LibStub, Ace3) are not committed. They're pulled in from `.pkgmeta`
by the [BigWigs packager](https://github.com/BigWigsMods/packager) when building a release.

## Licence

BSD 3-Clause, see [LICENSE](LICENSE). Embedded libraries keep their own licences, see
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
