#!/usr/bin/env bash
# Draws the player at the top of the menu in each state, on light and dark, into
# docs/menu-player.png. It is drawn by the app's own view code. Run it after changing how
# the player looks, and show the result in the PR.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

CLAUDE_FM_RENDER_DIR="$PWD/docs" swift test --filter MenuPlayerRenderTests
echo "Wrote docs/menu-player.png"
