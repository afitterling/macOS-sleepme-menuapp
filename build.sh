#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Lunair"
BUNDLE_ID="tech.sp33c.sleeptimer"
TEAM_ID="Q2ZG8FQS59"

# Marketing version and build number are set with ./setVersion and live
# in the VERSION and BUILD_NUMBER files.
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="$(tr -d '[:space:]' < BUILD_NUMBER)"

BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
PKG_ROOT="$BUILD_DIR/pkg-root"
PKG_FILE="$BUILD_DIR/$APP_NAME-$VERSION.pkg"

# Prefer a real Developer ID identity tied to the team so the build is
# notarizable; fall back to an ad-hoc signature on machines without the cert.
SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | grep "$TEAM_ID" \
    | head -1 | sed -E 's/.*"(.*)"/\1/')"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

swiftc -O -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" main.swift

# Regenerate the icon if missing, then bundle it.
[ -f AppIcon.icns ] || ./make-icon.sh
cp AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>             <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>      <string>Lunair</string>
    <key>CFBundleIdentifier</key>       <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>          <string>$BUILD_NUMBER</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleExecutable</key>       <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>         <string>AppIcon</string>
    <key>CFBundlePackageType</key>      <string>APPL</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSUIElement</key>              <true/>
    <key>LSMinimumSystemVersion</key>   <string>13.0</string>
    <key>NSAppleEventsUsageDescription</key><string>Lunair sleeps your Mac by asking System Events to sleep when a timer ends.</string>
</dict>
</plist>
EOF

if [ -n "$SIGN_IDENTITY" ]; then
    echo "Signing with: $SIGN_IDENTITY"
    codesign --force --timestamp --options runtime \
        --sign "$SIGN_IDENTITY" "$APP_BUNDLE" >/dev/null
else
    echo "No Developer ID for team $TEAM_ID found; ad-hoc signing."
    codesign --force --sign - "$APP_BUNDLE" >/dev/null
fi

echo "Built $APP_BUNDLE  (v$VERSION build $BUILD_NUMBER)"

# Stage the .app into a payload root mirroring the install location, then
# build a component installer pkg that drops it into /Applications.
mkdir -p "$PKG_ROOT/Applications"
cp -R "$APP_BUNDLE" "$PKG_ROOT/Applications/"

pkgbuild \
    --root "$PKG_ROOT" \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    --install-location "/" \
    "$PKG_FILE" >/dev/null

echo "Built $PKG_FILE"

# Open the project in Xcode (brings it forward if already running).
open Lunair.xcodeproj
