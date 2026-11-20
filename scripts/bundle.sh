#!/usr/bin/env bash
# Builds Claude FM.app into ./build. Pass --install to move it to ~/Applications and launch it.
#
# Environment, all optional:
#   CLAUDEFM_VERSION     The version to show, such as 1.2.0. Defaults to the latest v* tag.
#   CLAUDEFM_FEED_URL    The Sparkle feed. Set by scripts/release.sh, together with
#   CLAUDEFM_PUBLIC_KEY  the public key that updates are signed with. A build without
#                        these two never updates itself.
#   CODESIGN_IDENTITY    The signing identity. Defaults to a Developer ID Application
#                        certificate in the Keychain, or an ad-hoc signature without one.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/ClaudeFM"

APP="build/Claude FM.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeFM"

# The app icon. actool compiles the Icon Composer file into Assets.car, which macOS 26
# and later draw with the system's glass treatment, and AppIcon.icns for macOS 15.
# Info.plist names both below. scripts/render-icon.swift redraws the icon's artwork.
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" \
  --platform macosx --minimum-deployment-target 15.0 --app-icon AppIcon \
  --output-partial-info-plist "$(mktemp -d)/icon.plist" --errors --warnings \
  --output-format human-readable-text >/dev/null
for f in Assets.car AppIcon.icns; do
  [[ -f "$APP/Contents/Resources/$f" ]] || { echo "error: actool didn't produce $f" >&2; exit 1; }
done

# Sparkle, the updater. SwiftPM builds it next to the binary but doesn't know about
# app bundles, so copy it in and tell the binary where to find it.
ditto "$(dirname "$BIN")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/ClaudeFM"

# SwiftPM stamps the deployment target into the binary's SDK field, which puts AppKit
# into a compatibility mode. Stamp the real SDK version instead.
MIN_OS=15.0
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
xcrun vtool -set-build-version macos "$MIN_OS" "$SDK_VERSION" -replace \
  -output "$APP/Contents/MacOS/ClaudeFM" "$APP/Contents/MacOS/ClaudeFM"

# The version comes from the latest release tag. The build number is the number of
# commits, which only grows on main. Sparkle compares build numbers to find a newer build.
LATEST_TAG="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
VERSION="${CLAUDEFM_VERSION:-${LATEST_TAG#v}}"
VERSION="${VERSION:-1.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

UPDATER_KEYS=""
if [[ -n "${CLAUDEFM_FEED_URL:-}" && -n "${CLAUDEFM_PUBLIC_KEY:-}" ]]; then
  UPDATER_KEYS="<key>SUFeedURL</key><string>$CLAUDEFM_FEED_URL</string>
  <key>SUPublicEDKey</key><string>$CLAUDEFM_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUAutomaticallyUpdate</key><true/>"
fi

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
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  $UPDATER_KEYS
</dict>
</plist>
PLIST

# Sign with a Developer ID when the Keychain has one, so macOS on another Mac opens the
# app. Otherwise sign ad hoc.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ { print $2; exit }')}"
IDENTITY="${IDENTITY:--}"
SIGN=(codesign --force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then
  # Notarization needs the hardened runtime and a secure timestamp.
  SIGN+=(--options runtime --timestamp)
fi

# Sparkle's helpers are signed one at a time, innermost first, as its documentation says.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate"
"${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app"
"${SIGN[@]}" "$SPARKLE"
"${SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP, version $VERSION ($BUILD_NUMBER), signed with: $IDENTITY"

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
