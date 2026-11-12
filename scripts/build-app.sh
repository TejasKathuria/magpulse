#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"

echo "=== Building Magpulse for macOS ==="

# 1. Compile C Daemons & SMC Helpers
echo "Compiling C SMC helpers..."
clang -O3 -Wall -framework IOKit src/daemon/magpulse-daemon.c -o magpulse-daemon -lm
clang -O3 -Wall -framework IOKit aclc.c -o aclc
clang -O3 -Wall -framework IOKit aclc-pulse.c -o aclc-pulse -lm

# 2. Compile Swift GUI App
echo "Compiling Swift GUI application..."
CACHE_DIR="/tmp/swift-cache"
mkdir -p "$CACHE_DIR"

if [ -f "magpulselogo.png" ]; then
    echo "Generating AppIcon.icns from magpulselogo.png..."
    mkdir -p resources
    swift -module-cache-path "$CACHE_DIR" scripts/convert-logo-to-icns.swift magpulselogo.png resources/AppIcon.icns
fi

swiftc -O -parse-as-library \
    -module-cache-path "$CACHE_DIR" \
    -Xcc -fmodules-cache-path="$CACHE_DIR" \
    src/app/*.swift src/app/Views/*.swift \
    -o Magpulse-bin

# 3. Create .app Bundle Directory Structure
APP_BUNDLE="Magpulse.app"
echo "Creating $APP_BUNDLE bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 4. Copy Executables & Resources
cp Magpulse-bin "$APP_BUNDLE/Contents/MacOS/Magpulse"
chmod +x "$APP_BUNDLE/Contents/MacOS/Magpulse"

cp magpulse-daemon "$APP_BUNDLE/Contents/Resources/"
cp aclc "$APP_BUNDLE/Contents/Resources/"
cp aclc-pulse "$APP_BUNDLE/Contents/Resources/"
cp hooks/led-start.sh "$APP_BUNDLE/Contents/Resources/"
cp hooks/led-stop.sh "$APP_BUNDLE/Contents/Resources/"

if [ -f resources/AppIcon.icns ]; then
    cp resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# 5. Generate Info.plist
cat << 'EOF' > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Magpulse</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.magpulse.Magpulse</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Magpulse</string>
    <key>CFBundleDisplayName</key>
    <string>Magpulse</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

echo "=== Build Successful! ==="
echo "Application bundle created at: $DIR/Magpulse.app"

