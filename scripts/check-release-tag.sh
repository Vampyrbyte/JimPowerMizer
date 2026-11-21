#!/usr/bin/env bash
# Decide whether a tag may be released (run by the release workflow before packaging).
#   - Stable tags (vX.Y.Z): the tagged commit must be on main.
#   - Pre-release tags (containing "alpha" or "beta", e.g. v1.1.0-beta1): may come from another branch,
#     but must include all of main, so a beta never ships without the latest fixes.
# Usage: scripts/check-release-tag.sh <tag> [remote]   (remote defaults to origin: uses origin/main, ...)
set -euo pipefail

TAG="${1:?usage: check-release-tag.sh <tag> [remote]}"
REMOTE="${2:-origin}"
MAIN="$REMOTE/main"
COMMIT="$(git rev-parse --verify "$TAG^{commit}")"
git rev-parse --verify -q "$MAIN^{commit}" >/dev/null || { echo "::error::$MAIN not found"; exit 1; }

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

if ! git merge-base --is-ancestor "$MAIN" "$COMMIT"; then
	echo "::error::$TAG doesn't include the latest main. Merge main into the branch, then tag again."
	exit 1
fi
echo "$TAG includes all of main: OK"
echo "$TAG is a pre-release: OK"
