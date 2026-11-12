#!/bin/bash
cat >/dev/null
rm -f /tmp/cursor-led.active /tmp/magpulse.active
sleep 0.3
sudo -n /usr/local/bin/aclc 0 2>/dev/null || sudo -n /usr/local/bin/magpulse-daemon set 0 2>/dev/null || true
echo '{}'
