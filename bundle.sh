#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Building release binary..."
swift build -c release

APP_DIR="OpenSwitcher.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Creating .app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp .build/release/OpenSwitcher "$MACOS_DIR/OpenSwitcher"

VERSION="${APP_VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "1.0.7")}"
echo "Packaging OpenSwitcher version $VERSION..."

cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>OpenSwitcher</string>
    <key>CFBundleIdentifier</key>
    <string>io.openswitcher.app</string>
    <key>CFBundleName</key>
    <string>OpenSwitcher</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
EOF

echo "Signing .app bundle..."
KC="$HOME/Library/Keychains/openswitcher.keychain-db"
if [ -f "$KC" ]; then
    security unlock-keychain -p "openswitcher_pass" "$KC" 2>/dev/null || true
    codesign --force --deep --keychain "$KC" -s "OpenSwitcher Dev" "$APP_DIR"
else
    codesign --force --deep -s - "$APP_DIR"
fi

echo "OpenSwitcher.app created successfully at $(pwd)/$APP_DIR"

