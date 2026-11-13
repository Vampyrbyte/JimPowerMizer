#!/usr/bin/env bash
# Fetch the embedded libraries into Libs/ for local development.
# Release builds get them from .pkgmeta via the BigWigs packager instead.
# Ace3's GitHub repo also contains LibStub and CallbackHandler-1.0.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBS=(LibStub CallbackHandler-1.0 AceAddon-3.0 AceEvent-3.0 AceTimer-3.0 AceConsole-3.0
      AceDB-3.0 AceDBOptions-3.0 AceGUI-3.0 AceConfig-3.0 AceLocale-3.0)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git clone --quiet --depth 1 https://github.com/WoWUIDev/Ace3.git "$TMP/Ace3"

mkdir -p "$ROOT/Libs"
for lib in "${LIBS[@]}"; do
	rm -rf "${ROOT:?}/Libs/$lib"
	cp -r "$TMP/Ace3/$lib" "$ROOT/Libs/$lib"
done
echo "Fetched ${#LIBS[@]} libraries into Libs/ (Ace3 $(git -C "$TMP/Ace3" rev-parse --short HEAD))"
