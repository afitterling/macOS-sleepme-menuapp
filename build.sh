#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="SleepTimer"
BUNDLE_ID="tech.sp33c.sleeptimer"
VERSION="1.0"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
PKG_ROOT="$BUILD_DIR/pkg-root"
PKG_FILE="$BUILD_DIR/$APP_NAME-$VERSION.pkg"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"

swiftc -O -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" main.swift

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>             <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>      <string>Sleep Timer</string>
    <key>CFBundleIdentifier</key>       <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>          <string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleExecutable</key>       <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>      <string>APPL</string>
    <key>LSUIElement</key>              <true/>
    <key>LSMinimumSystemVersion</key>   <string>11.0</string>
</dict>
</plist>
EOF

# Ad-hoc sign so Gatekeeper doesn't refuse to launch the unsigned binary.
codesign --force --sign - "$APP_BUNDLE" >/dev/null

echo "Built $APP_BUNDLE"

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
