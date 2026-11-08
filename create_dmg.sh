#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "1. Building fresh OpenSwitcher.app..."
./bundle.sh

DMG_NAME="OpenSwitcher.dmg"
STAGING_DIR="dmg_staging"

echo "2. Preparing staging folder..."
rm -rf "$STAGING_DIR" "$DMG_NAME"
mkdir -p "$STAGING_DIR"

cp -R OpenSwitcher.app "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "3. Creating compressed DMG..."
hdiutil create \
    -volname "OpenSwitcher" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_NAME"

rm -rf "$STAGING_DIR"

echo "=========================================="
echo "Successfully created: $(pwd)/$DMG_NAME"
echo "Size: $(du -h "$DMG_NAME" | cut -f1)"
echo "=========================================="
