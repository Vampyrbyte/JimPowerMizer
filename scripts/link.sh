#!/usr/bin/env bash
# Link this repo (or worktree) into a game's AddOns folder as a separate dev copy,
# JimPowerMizerDev, so it can sit next to the release install (AddOns/JimPowerMizer). Enable one
# of the two at a time in the game's AddOns list. Each keeps its own settings (saved variables are
# stored per folder).
#
# The game only reads TOCs named after the folder, so for each release TOC (JimPowerMizer_Mainline.toc,
# JimPowerMizer_Classic.toc, ...) this writes a gitignored JimPowerMizerDev_<suffix>.toc with a dev
# title and version; each client picks the one for its family. Run it again after a release TOC
# changes (e.g. a new file), or the dev copy won't load that file.
#
# Usage: scripts/link.sh [--forever | --retail | --classic-era | --anniversary | --classic
#                         | path/to/World of Warcraft/_flavor_]
#   --forever (default)  <WoW>/_forever_
#   --retail             <WoW>/_retail_ (Midnight)
#   --classic-era        <WoW>/_classic_era_ (Classic Era, Season of Discovery, Hardcore)
#   --anniversary        <WoW>/_anniversary_ (TBC Anniversary)
#   --classic            <WoW>/_classic_ (Mists of Pandaria Classic)
# <WoW> is $WOW_DIR, defaulting to the Faugus Battle.net prefix on this machine. A path, or
# $WOW_FOREVER_DIR for the default, overrides it.
#
# Running this from another worktree (e.g. the midnight branch) points that game's dev copy at
# that worktree; run it from the main checkout to point it back.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WOW_DIR="${WOW_DIR:-$HOME/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft}"
case "${1:---forever}" in
	--forever) GAME_DIR="${WOW_FOREVER_DIR:-$WOW_DIR/_forever_}" ;;
	--retail)  GAME_DIR="$WOW_DIR/_retail_" ;;
	--classic-era) GAME_DIR="$WOW_DIR/_classic_era_" ;;
	--anniversary) GAME_DIR="$WOW_DIR/_anniversary_" ;;
	--classic) GAME_DIR="$WOW_DIR/_classic_" ;;
	-*)        echo "Unknown option $1 (use --forever, --retail, --classic-era, --anniversary, --classic or a game folder)" >&2; exit 1 ;;
	*)         GAME_DIR="$1" ;;
esac
ADDONS="$GAME_DIR/Interface/AddOns"
NAME="JimPowerMizerDev"
TARGET="$ADDONS/$NAME"

[[ -d "$GAME_DIR" ]] || { echo "Game folder not found: $GAME_DIR" >&2; exit 1; }
[[ -d "$ROOT/Libs/AceAddon-3.0" ]] || { echo "Libs/ missing: run scripts/fetch-libs.sh first" >&2; exit 1; }
mkdir -p "$ADDONS"

# Dev TOCs: same file list and saved variables, dev title and version. One per release TOC; dev TOCs
# left from a release TOC that no longer exists on this branch are removed.
shopt -s nullglob
for dev_toc in "$ROOT/${NAME}"_*.toc; do
	[[ -e "$ROOT/JimPowerMizer_${dev_toc##*/${NAME}_}" ]] || { rm "$dev_toc"; echo "Removed $dev_toc"; }
done
release_tocs=("$ROOT"/JimPowerMizer_*.toc)
(( ${#release_tocs[@]} )) || { echo "No JimPowerMizer_*.toc in $ROOT" >&2; exit 1; }
for release_toc in "${release_tocs[@]}"; do
	dev_toc="$ROOT/${NAME}_${release_toc##*/JimPowerMizer_}"
	sed -e 's/^## Title: .*/## Title: JimPowerMizer |cffff8000(dev)|r/' \
	    -e 's/^## Version: .*/## Version: dev/' \
	    "$release_toc" > "$dev_toc"
	grep -q '^## Title: JimPowerMizer |cffff8000(dev)|r' "$dev_toc" && grep -q '^## Version: dev' "$dev_toc" \
		|| { echo "Couldn't set the dev title/version in $dev_toc" >&2; exit 1; }
	echo "Wrote $dev_toc"
done

# The first dev setup linked the repo as AddOns/JimPowerMizer, where the release now goes.
OLD="$ADDONS/JimPowerMizer"
if [[ -L "$OLD" && "$(readlink -f "$OLD")" == "$ROOT" ]]; then
	rm "$OLD"
	echo "Removed the old dev link $OLD (install the release there)"
fi

if [[ -L "$TARGET" ]]; then
	rm "$TARGET"
elif [[ -e "$TARGET" ]]; then
	echo "$TARGET exists and is not a symlink; move it away first" >&2
	exit 1
fi
ln -s "$ROOT" "$TARGET"
echo "Linked $TARGET -> $ROOT"
