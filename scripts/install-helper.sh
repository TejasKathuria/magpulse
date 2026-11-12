#!/bin/bash
# Standalone helper installer for Magpulse
set -e

DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"

echo "=== Magpulse Helper Installation ==="

# Check binaries
[ -f "./magpulse-daemon" ] || [ -f "./Magpulse.app/Contents/Resources/magpulse-daemon" ] || {
    echo "Building binaries first..."
    ./scripts/build-app.sh
}

DAEMON_SRC="./magpulse-daemon"
[ -f "$DAEMON_SRC" ] || DAEMON_SRC="./Magpulse.app/Contents/Resources/magpulse-daemon"

echo "1. Installing binaries to /usr/local/bin..."
sudo mkdir -p /usr/local/bin
sudo cp -f "$DAEMON_SRC" /usr/local/bin/magpulse-daemon
sudo chmod 755 /usr/local/bin/magpulse-daemon
sudo ln -sf /usr/local/bin/magpulse-daemon /usr/local/bin/aclc
sudo ln -sf /usr/local/bin/magpulse-daemon /usr/local/bin/aclc-pulse

echo "2. Setting up passwordless sudo rule for Magpulse..."
USER_NAME="$(whoami)"
RULE="$USER_NAME ALL=(root) NOPASSWD: /usr/local/bin/magpulse-daemon, /usr/local/bin/aclc, /usr/local/bin/aclc-pulse"

TMP_FILE="$(mktemp)"
echo "$RULE" > "$TMP_FILE"

if sudo visudo -cf "$TMP_FILE" >/dev/null 2>&1; then
    sudo cp "$TMP_FILE" /etc/sudoers.d/magpulse
    sudo chmod 440 /etc/sudoers.d/magpulse
    echo "Sudoers rule installed to /etc/sudoers.d/magpulse"
else
    echo "Error: Sudoers rule validation failed."
    rm -f "$TMP_FILE"
    exit 1
fi
rm -f "$TMP_FILE"

echo ""
echo "=== Done! Magpulse helper is installed and ready. ==="
echo "You can now launch Magpulse.app or run: sudo magpulse-daemon test amber 2.0"

