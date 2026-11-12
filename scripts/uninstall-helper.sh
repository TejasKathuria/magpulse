#!/bin/bash
# Standalone uninstaller for Magpulse helper
set -e

echo "=== Uninstalling Magpulse Helper ==="

# Reset SMC to system default
sudo -n /usr/local/bin/aclc 0 2>/dev/null || true

# Remove binaries and sudoers rule
sudo rm -f /usr/local/bin/magpulse-daemon /usr/local/bin/aclc /usr/local/bin/aclc-pulse
sudo rm -f /etc/sudoers.d/magpulse /etc/sudoers.d/aclc

# Stop any running daemon
pkill -x magpulse-daemon 2>/dev/null || true
pkill -x aclc-pulse 2>/dev/null || true

echo "=== Magpulse helper successfully uninstalled! ==="

