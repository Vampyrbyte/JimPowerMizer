#!/usr/bin/env bash
# Print the release notes for a tag: docs/releases/<tag>.md, followed by the AI disclosure. The
# release workflow writes this to .release-notes.md, which .pkgmeta names as the packager's manual
# changelog (GitHub release, CurseForge and Wago). Fails if the tag has no notes file.
#
# Usage: scripts/release-notes.sh <tag>
#
# The models in the disclosure come from the Co-Authored-By lines of every commit the tag contains,
# in order of first use, so a new model is listed without editing anything here.
set -euo pipefail

TAG="${1:?usage: $0 <tag>}"
cd "$(dirname "$0")/.."

NOTES="docs/releases/$TAG.md"
if [ ! -f "$NOTES" ]; then
	echo "::error::No release notes for $TAG: write $NOTES on main (and merge main into the branch being tagged)." >&2
	exit 1
fi

REF="$TAG"
git rev-parse --verify -q "$REF^{commit}" >/dev/null || REF=HEAD # notes previewed before tagging

models=$(git log --reverse --format='%(trailers:key=Co-Authored-By,valueonly)' "$REF" \
	| sed -n 's/^\(Claude [^<]*[^< ]\) *<.*/\1/p' | awk '!seen[$0]++')
list=""
count=$(printf '%s\n' "$models" | grep -c . || true)
i=0
while IFS= read -r model; do
	[ -n "$model" ] || continue
	i=$((i + 1))
	if [ "$i" -eq 1 ]; then list="$model"
	elif [ "$i" -eq "$count" ]; then list="$list and $model"
	else list="$list, $model"
	fi
done <<< "$models"

cat "$NOTES"
printf '\n---\n\n'
if [ -n "$list" ]; then
	printf '**AI disclosure:** JimPowerMizer is developed with the help of AI. Code, tests and documentation, these notes included, are written with Claude Code (Anthropic), using %s. The author directs the work and tests changes in game.\n' "$list"
else
	printf '**AI disclosure:** JimPowerMizer is developed with the help of AI (Claude Code, Anthropic). The author directs the work and tests changes in game.\n'
fi
