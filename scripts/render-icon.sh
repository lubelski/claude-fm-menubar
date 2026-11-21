#!/usr/bin/env bash
# Redraws the app icon's artwork, Resources/AppIcon.icon/Assets/radio.png, from the app's
# radio drawing. Run it after changing how the radio looks. bundle.sh compiles the icon itself.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

xcrun swiftc -O -o "$WORK/render-icon" scripts/icon/main.swift Sources/ClaudeFM/RadioDrawing.swift
"$WORK/render-icon" Resources/AppIcon.icon/Assets/radio.png
