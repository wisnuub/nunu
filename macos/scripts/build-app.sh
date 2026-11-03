#!/bin/bash
# Builds macos/build/nunu.app (and optionally a DMG) from the Swift package.
#   scripts/build-app.sh            release build, ad-hoc signed
#   scripts/build-app.sh --dmg      also writes build/nunu-<version>-arm64.dmg
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
VERSION=$(node -p "require('../package.json').version" 2>/dev/null || echo "0.1.0")
APP="$ROOT/build/nunu.app"

swift build -c release --arch arm64
BIN=$(swift build -c release --arch arm64 --show-bin-path)/Nunu

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/nunu"
cp ../assets/icon.icns "$APP/Contents/Resources/icon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.nunu.launcher</string>
  <key>CFBundleName</key><string>nunu</string>
  <key>CFBundleDisplayName</key><string>nunu</string>
  <key>CFBundleExecutable</key><string>nunu</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>LSArchitecturePriority</key><array><string>arm64</string></array>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><false/>
  <key>NSHumanReadableCopyright</key><string>nunu</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Android app</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Default</string>
      <key>CFBundleTypeExtensions</key><array><string>apk</string><string>apks</string><string>xapk</string></array>
    </dict>
  </array>
</dict>
</plist>
EOF

# nunu itself needs no special entitlements: the Hypervisor.framework
# entitlement lives on Google's engine binary, which is signed by Google.
codesign --force --sign - --options runtime "$APP"
echo "built $APP ($VERSION)"

if [[ "${1:-}" == "--dmg" ]]; then
  DMG="$ROOT/build/nunu-$VERSION-arm64.dmg"
  STAGING=$(mktemp -d)
  cp -R "$APP" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname nunu -srcfolder "$STAGING" -ov -format UDZO -imagekey zlib-level=9 "$DMG"
  rm -rf "$STAGING"
  echo "built $DMG"
fi
