#!/usr/bin/env bash
# Link this repo into the game's AddOns folder as a separate dev copy, JimPowerMizerDev, so it
# can sit next to the release install (AddOns/JimPowerMizer). Enable one of the two at a time in
# the game's AddOns list. Each keeps its own settings (saved variables are stored per folder).
#
# The game only reads the TOC named after the folder, so this writes JimPowerMizerDev_Mainline.toc
# (gitignored) from JimPowerMizer_Mainline.toc with a dev title and version. Run it again after
# the release TOC changes (e.g. a new file), or the dev copy won't load that file.
#
# Usage: scripts/link.sh [path/to/World of Warcraft/_forever_]
# Defaults to $WOW_FOREVER_DIR, then the Faugus Battle.net prefix on this machine.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_DIR="${1:-${WOW_FOREVER_DIR:-$HOME/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_}}"
ADDONS="$GAME_DIR/Interface/AddOns"
NAME="JimPowerMizerDev"
TARGET="$ADDONS/$NAME"
RELEASE_TOC="$ROOT/JimPowerMizer_Mainline.toc"
DEV_TOC="$ROOT/${NAME}_Mainline.toc"

[[ -d "$GAME_DIR" ]] || { echo "Game folder not found: $GAME_DIR" >&2; exit 1; }
[[ -d "$ROOT/Libs/AceAddon-3.0" ]] || { echo "Libs/ missing: run scripts/fetch-libs.sh first" >&2; exit 1; }
mkdir -p "$ADDONS"

# Dev TOC: same file list and saved variables, dev title and version.
sed -e 's/^## Title: .*/## Title: JimPowerMizer |cffff8000(dev)|r/' \
    -e 's/^## Version: .*/## Version: dev/' \
    "$RELEASE_TOC" > "$DEV_TOC"
grep -q '^## Title: JimPowerMizer |cffff8000(dev)|r' "$DEV_TOC" && grep -q '^## Version: dev' "$DEV_TOC" \
	|| { echo "Couldn't set the dev title/version in $DEV_TOC" >&2; exit 1; }
echo "Wrote $DEV_TOC"

# The old setup linked the repo as AddOns/JimPowerMizer, where the release now goes.
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
