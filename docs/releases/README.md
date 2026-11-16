# Release notes

One file per release, named after its tag (`v0.1.5.md`, `v0.2.0-beta2.md`), written on `main` before
tagging and merged into the branch being tagged. The release workflow refuses a tag without one.
`scripts/release-notes.sh <tag>` prints the notes as published: the file plus the AI disclosure, whose
model list comes from the commits' Co-Authored-By lines.

For players who like detail (decided 2026-11-16):
- Only what changes in the addon. No tooling, CI, tests, planning or docs.
- Headline features first, then smaller changes, then fixes.
- Technical is fine: CVar names, commands, events, how something is worked out, known limits.
- A beta says which clients it is for and what feedback is wanted.

Layout:

```markdown
## JimPowerMizer vX.Y.Z

### New: <headline feature>
What it does, how to use it, details and limits.

### Changes
- ...

### Fixes
- What went wrong, when, and what happens now.
```
