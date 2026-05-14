#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="SleepTimer"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

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
    <key>CFBundleIdentifier</key>       <string>tech.sp33c.sleeptimer</string>
    <key>CFBundleVersion</key>          <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key>       <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>      <string>APPL</string>
    <key>LSUIElement</key>              <true/>
    <key>LSMinimumSystemVersion</key>   <string>11.0</string>
</dict>
</plist>
EOF

echo "Built $APP_BUNDLE"
