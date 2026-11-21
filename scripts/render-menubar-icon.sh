#!/usr/bin/env bash
# Renders the menu bar icon in each player state, on light and dark menu bars, into docs/:
# menubar-icon.gif animates through the states and menubar-icon.png is a still of each.
# Run it after changing how the menu bar icon looks or moves, and show the result in the PR.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

xcrun swiftc -O -o "$WORK/render-menubar-icon" scripts/menubar-icon/main.swift \
  Sources/ClaudeFM/RadioIcon.swift Sources/ClaudeFM/RadioDrawing.swift
"$WORK/render-menubar-icon" docs
