#!/usr/bin/env bash
# Symlink this repo into the game's AddOns folder for development.
# Usage: scripts/link.sh [path/to/World of Warcraft/_forever_]
# Defaults to $WOW_FOREVER_DIR, then the Faugus Battle.net prefix on this machine.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_DIR="${1:-${WOW_FOREVER_DIR:-$HOME/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_}}"
ADDONS="$GAME_DIR/Interface/AddOns"
TARGET="$ADDONS/JimPowerMizer"

[[ -d "$GAME_DIR" ]] || { echo "Game folder not found: $GAME_DIR" >&2; exit 1; }
[[ -d "$ROOT/Libs/AceAddon-3.0" ]] || { echo "Libs/ missing: run scripts/fetch-libs.sh first" >&2; exit 1; }
mkdir -p "$ADDONS"

if [[ -L "$TARGET" ]]; then
	rm "$TARGET"
elif [[ -e "$TARGET" ]]; then
	echo "$TARGET exists and is not a symlink; move it away first" >&2
	exit 1
fi
ln -s "$ROOT" "$TARGET"
echo "Linked $TARGET -> $ROOT"
