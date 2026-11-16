#!/usr/bin/env bash
# Decide whether a tag may be released (run by the release workflow before packaging).
#   - Stable tags (vX.Y.Z): the tagged commit must be on main.
#   - Pre-release tags (containing "alpha" or "beta", e.g. v0.2.0-beta1): may come from another branch
#     (e.g. midnight), but must include all of main, plus every branch its version line builds on
#     (UPSTREAM below), so a beta never ships without the latest fixes from the branches above it.
#   - Until 0.2.0 is stable, 0.3 pre-releases are for the Classic clients only: the tagged .pkgmeta must
#     leave out JimPowerMizer_Mainline.toc, or they'd replace the 0.2 betas for Forever and Midnight
#     (docs/PLAN.md, M6).
# Usage: scripts/check-release-tag.sh <tag> [remote]   (remote defaults to origin: uses origin/main, ...)
set -euo pipefail

TAG="${1:?usage: check-release-tag.sh <tag> [remote]}"
REMOTE="${2:-origin}"
MAIN="$REMOTE/main"
COMMIT="$(git rev-parse --verify "$TAG^{commit}")"
git rev-parse --verify -q "$MAIN^{commit}" >/dev/null || { echo "::error::$MAIN not found"; exit 1; }

# Version line -> branches besides main that its pre-releases must include. A branch that no longer
# exists (merged and deleted) is skipped.
declare -A UPSTREAM=( [0.3]="midnight" )
LINE="$(sed -nE 's/^v([0-9]+\.[0-9]+)\..*/\1/p' <<< "$TAG")"

case "$TAG" in
	*alpha*|*beta*) ;;
	*)
		if git merge-base --is-ancestor "$COMMIT" "$MAIN"; then
			echo "$TAG is on main: OK"
			exit 0
		fi
		echo "::error::$TAG isn't on main. Stable releases come from main only (pre-release tags need alpha or beta in the name)."
		exit 1
		;;
esac

for branch in main ${UPSTREAM[$LINE]:-}; do
	ref="$REMOTE/$branch"
	if ! git rev-parse --verify -q "$ref^{commit}" >/dev/null; then
		echo "$ref doesn't exist (merged and deleted?): skipped"
		continue
	fi
	if ! git merge-base --is-ancestor "$ref" "$COMMIT"; then
		echo "::error::$TAG doesn't include the latest $branch. Merge $branch into the branch, then tag again."
		exit 1
	fi
	echo "$TAG includes all of $branch: OK"
done

if [[ "$LINE" == "0.3" ]]; then
	stable_02="$(git tag -l 'v0.2.*' | grep -v -i -E 'alpha|beta' || true)"
	if [[ -n "$stable_02" ]]; then
		echo "0.2 is stable ($(head -n1 <<< "$stable_02")): 0.3 pre-releases may go to every client"
	elif git show "$COMMIT:.pkgmeta" 2>/dev/null | grep -qE '^[[:space:]]*-[[:space:]]*JimPowerMizer_Mainline\.toc[[:space:]]*$'; then
		echo "$TAG leaves out the Mainline TOC (Classic clients only): OK"
	else
		echo "::error::0.2 isn't stable yet, so 0.3 pre-releases must be for Classic only: add '  - JimPowerMizer_Mainline.toc' under ignore: in .pkgmeta on the classic branch."
		exit 1
	fi
fi
echo "$TAG is a pre-release: OK"
