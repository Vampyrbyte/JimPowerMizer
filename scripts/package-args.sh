#!/usr/bin/env bash
# Extra packager arguments for the release workflow, printed on one line (nothing when none are needed).
#
# The packager labels an upload with the game versions of every TOC in the repository, even one that
# .pkgmeta leaves out of the package. When a TOC is left out (the classic branch once left out the Mainline
# TOC until 0.2.0 is stable, docs/PLAN.md M6), this prints "-g <versions>" with the versions of the
# TOCs that are packaged, so the upload is labelled only for the clients it supports.
# Usage: scripts/package-args.sh [repo root]   (default: this script's repo)
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ignored() { # is $1 (a file name) listed under ignore: in .pkgmeta?
	[[ -f "$ROOT/.pkgmeta" ]] && grep -qE "^[[:space:]]*-[[:space:]]*${1//./\\.}[[:space:]]*$" "$ROOT/.pkgmeta"
}

shopt -s nullglob
versions=() left_out=0
for toc in "$ROOT"/JimPowerMizer_*.toc; do
	name="${toc##*/}"
	if ignored "$name"; then left_out=1; continue; fi
	line="$(sed -n 's/^## Interface:[[:space:]]*//p' "$toc" | tr -d '\r' | head -n1)"
	IFS=',' read -ra interfaces <<< "$line"
	for i in "${interfaces[@]}"; do
		i="${i//[[:space:]]/}"
		[[ "$i" =~ ^[0-9]{5,6}$ ]] || { echo "Bad interface '$i' in $name" >&2; exit 1; }
		versions+=("$(( 10#${i:0:-4} )).$(( 10#${i: -4:2} )).$(( 10#${i: -2} ))")
	done
done
(( left_out )) || exit 0
(( ${#versions[@]} )) || { echo "Every TOC is left out of the package" >&2; exit 1; }
IFS=','; echo "-g ${versions[*]}"
