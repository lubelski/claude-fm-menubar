#!/usr/bin/env bash
# Builds Claude FM.app into ./build. Pass --install to move it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/ClaudeFM"

APP="build/Claude FM.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ClaudeFM"

# SwiftPM stamps the deployment target into the binary's SDK field, which puts AppKit
# into a compatibility mode. Stamp the real SDK version instead.
MIN_OS=15.0
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
xcrun vtool -set-build-version macos "$MIN_OS" "$SDK_VERSION" -replace \
  -output "$APP/Contents/MacOS/ClaudeFM" "$APP/Contents/MacOS/ClaudeFM"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Claude FM</string>
  <key>CFBundleDisplayName</key><string>Claude FM</string>
  <key>CFBundleIdentifier</key><string>dev.lubelski.ClaudeFM</string>
  <key>CFBundleExecutable</key><string>ClaudeFM</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST=~/Applications/"Claude FM.app"
  if pkill -x ClaudeFM; then
    for _ in {1..50}; do
      pgrep -x ClaudeFM >/dev/null || break
      sleep 0.1
    done
    pkill -9 -x ClaudeFM || true
  fi
  mkdir -p ~/Applications
  rm -rf "$DEST"
  mv "$APP" "$DEST"
  open "$DEST"
  echo "Installed and launched $DEST"
fi
