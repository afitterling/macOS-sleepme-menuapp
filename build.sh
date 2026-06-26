#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="BedTime"
BUNDLE_ID="tech.sp33c.bedtime"
TEAM_ID="Q2ZG8FQS59"

# Marketing version lives in the VERSION file; the build number is derived
# from the git history so every commit yields a unique, monotonic value.
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

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
mkdir -p "$APP_BUNDLE/Contents/MacOS"

swiftc -O -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" main.swift

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>             <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>      <string>BedTime</string>
    <key>CFBundleIdentifier</key>       <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>          <string>$BUILD_NUMBER</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleExecutable</key>       <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>      <string>APPL</string>
    <key>LSUIElement</key>              <true/>
    <key>LSMinimumSystemVersion</key>   <string>11.0</string>
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
open -a Xcode "$(pwd)"
