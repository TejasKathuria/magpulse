#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"

echo "=== Creating Magpulse DMG Installer ==="

# 1. Ensure Magpulse.app is built
if [ ! -d "Magpulse.app" ]; then
    echo "Magpulse.app not found. Building first..."
    ./scripts/build-app.sh
fi

STAGING_DIR="/tmp/magpulse-dmg-staging"
DMG_NAME="Magpulse.dmg"

echo "1. Preparing staging directory..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

echo "2. Copying Magpulse.app..."
cp -R "Magpulse.app" "$STAGING_DIR/"

echo "3. Creating Applications symlink..."
ln -s /Applications "$STAGING_DIR/Applications"

echo "4. Setting volume icon..."
if [ -f "resources/AppIcon.icns" ]; then
    cp "resources/AppIcon.icns" "$STAGING_DIR/.VolumeIcon.icns"
fi

echo "5. Building compressed DMG image..."
rm -f "$DMG_NAME"
hdiutil create -volname "Magpulse" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_NAME"

echo "6. Cleaning up temporary files..."
rm -rf "$STAGING_DIR"

echo ""
echo "=== Success! ==="
echo "DMG created at: $DIR/$DMG_NAME"
ls -lh "$DIR/$DMG_NAME"
